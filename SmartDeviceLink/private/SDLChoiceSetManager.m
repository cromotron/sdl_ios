//
//  SDLChoiceSetManager.m
//  SmartDeviceLink
//
//  Created by Joel Fischer on 5/21/18.
//  Copyright © 2018 smartdevicelink. All rights reserved.
//

#import "SDLChoiceSetManager.h"

#import "SmartDeviceLink.h"

#import "SDLCheckChoiceVROptionalOperation.h"
#import "SDLDeleteChoicesOperation.h"
#import "SDLError.h"
#import "SDLGlobals.h"
#import "SDLPreloadChoicesOperation.h"
#import "SDLPresentChoiceSetOperation.h"
#import "SDLPresentKeyboardOperation.h"
#import "SDLRPCNotificationNotification.h"
#import "SDLRPCResponseNotification.h"
#import "SDLStateMachine.h"
#import "SDLVersion.h"
#import "SDLWindowCapability+ScreenManagerExtensions.h"

NS_ASSUME_NONNULL_BEGIN

SDLChoiceManagerState *const SDLChoiceManagerStateShutdown = @"Shutdown";
SDLChoiceManagerState *const SDLChoiceManagerStateCheckingVoiceOptional = @"CheckingVoiceOptional";
SDLChoiceManagerState *const SDLChoiceManagerStateReady = @"Ready";
SDLChoiceManagerState *const SDLChoiceManagerStateStartupError = @"StartupError";

typedef NSNumber * SDLChoiceId;

@interface SDLChoiceCell()

@property (assign, nonatomic) UInt16 choiceId;
@property (strong, nonatomic, readwrite) NSString *uniqueText;
@property (copy, nonatomic, readwrite, nullable) NSString *secondaryText;
@property (copy, nonatomic, readwrite, nullable) NSString *tertiaryText;
@property (copy, nonatomic, readwrite, nullable) NSArray<NSString *> *voiceCommands;
@property (strong, nonatomic, readwrite, nullable) SDLArtwork *artwork;
@property (strong, nonatomic, readwrite, nullable) SDLArtwork *secondaryArtwork;

@end

@interface SDLChoiceSetManager()

@property (weak, nonatomic) id<SDLConnectionManagerType> connectionManager;
@property (weak, nonatomic) SDLFileManager *fileManager;
@property (weak, nonatomic) SDLSystemCapabilityManager *systemCapabilityManager;

@property (strong, nonatomic, readonly) SDLStateMachine *stateMachine;
@property (strong, nonatomic) NSOperationQueue *transactionQueue;
@property (copy, nonatomic) dispatch_queue_t readWriteQueue;

@property (copy, nonatomic, nullable) SDLHMILevel currentHMILevel;
@property (copy, nonatomic, nullable) SDLWindowCapability *currentWindowCapability;

@property (assign, nonatomic) UInt16 nextChoiceId;
@property (assign, nonatomic) UInt16 nextCancelId;
@property (assign, nonatomic, getter=isVROptional) BOOL vrOptional;
@property (copy, nonatomic, readwrite) NSSet<SDLChoiceCell *> *preloadedChoices;

@end

UInt16 const ChoiceCellIdMin = 1;

// Assigns a set range of unique cancel ids in order to prevent overlap with other sub-screen managers that use cancel ids. If the max cancel id is reached, generation starts over from the cancel id min value.
UInt16 const ChoiceCellCancelIdMin = 101;
UInt16 const ChoiceCellCancelIdMax = 200;

@implementation SDLChoiceSetManager

#pragma mark - Lifecycle

- (instancetype)initWithConnectionManager:(id<SDLConnectionManagerType>)connectionManager fileManager:(SDLFileManager *)fileManager systemCapabilityManager:(SDLSystemCapabilityManager *)systemCapabilityManager {
    self = [super init];
    if (!self) { return nil; }

    _connectionManager = connectionManager;
    _fileManager = fileManager;
    _systemCapabilityManager = systemCapabilityManager;
    _stateMachine = [[SDLStateMachine alloc] initWithTarget:self initialState:SDLChoiceManagerStateShutdown states:[self.class sdl_stateTransitionDictionary]];
    _transactionQueue = [self sdl_newTransactionQueue];

    _readWriteQueue = dispatch_queue_create_with_target("com.sdl.screenManager.choiceSetManager.readWriteQueue", DISPATCH_QUEUE_SERIAL, [SDLGlobals sharedGlobals].sdlProcessingQueue);

    _preloadedChoices = [NSSet set];

    _nextChoiceId = ChoiceCellIdMin;
    _nextCancelId = ChoiceCellCancelIdMin;
    _vrOptional = YES;
    _keyboardConfiguration = [self sdl_defaultKeyboardConfiguration];
    _currentHMILevel = SDLHMILevelNone;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sdl_hmiStatusNotification:) name:SDLDidChangeHMIStatusNotification object:nil];

    return self;
}

- (void)start {
    SDLLogD(@"Starting manager");

    [self.systemCapabilityManager subscribeToCapabilityType:SDLSystemCapabilityTypeDisplays withObserver:self selector:@selector(sdl_displayCapabilityDidUpdate)];

    if ([self.currentState isEqualToString:SDLChoiceManagerStateShutdown]) {
        [self.stateMachine transitionToState:SDLChoiceManagerStateCheckingVoiceOptional];
    }

    // Else, we're already started
}

- (void)stop {
    SDLLogD(@"Stopping manager");
    
    [SDLGlobals runSyncOnSerialSubQueue:self.readWriteQueue block:^{
        [self.stateMachine transitionToState:SDLChoiceManagerStateShutdown];
    }];
}

+ (NSDictionary<SDLState *, SDLAllowableStateTransitions *> *)sdl_stateTransitionDictionary {
    return @{
             SDLChoiceManagerStateShutdown: @[SDLChoiceManagerStateCheckingVoiceOptional],
             SDLChoiceManagerStateCheckingVoiceOptional: @[SDLChoiceManagerStateShutdown, SDLChoiceManagerStateReady, SDLChoiceManagerStateStartupError],
             SDLChoiceManagerStateReady: @[SDLChoiceManagerStateShutdown],
             SDLChoiceManagerStateStartupError: @[SDLChoiceManagerStateShutdown]
             };
}

- (NSOperationQueue *)sdl_newTransactionQueue {
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.name = @"com.sdl.screenManager.choiceSetManager.transactionQueue";
    queue.maxConcurrentOperationCount = 1;
    queue.qualityOfService = NSQualityOfServiceUserInteractive;
    queue.underlyingQueue = [SDLGlobals sharedGlobals].sdlConcurrentQueue;
    queue.suspended = YES;

    return queue;
}

/// Suspend the transaction queue if we are in HMI NONE
/// OR if the text field name "menu name" (i.e. is the primary choice text) cannot be used, we assume we cannot present a PI.
- (void)sdl_updateTransactionQueueSuspended {
    if ([self.currentHMILevel isEqualToEnum:SDLHMILevelNone]
        || (![self.currentWindowCapability hasTextFieldOfName:SDLTextFieldNameMenuName])) {
        SDLLogD(@"Suspending the transaction queue. Current HMI level is: %@, window capability has MenuName (choice primary text): %@", self.currentHMILevel, ([self.currentWindowCapability hasTextFieldOfName:SDLTextFieldNameMenuName] ? @"YES" : @"NO"));
        self.transactionQueue.suspended = YES;
    } else {
        SDLLogD(@"Starting the transaction queue");
        self.transactionQueue.suspended = NO;
    }
}

#pragma mark - State Management

- (void)didEnterStateShutdown {
    SDLLogV(@"Manager shutting down");

    NSAssert(dispatch_get_specific(SDLProcessingQueueName) != nil, @"%@ must only be called on the SDL serial queue", NSStringFromSelector(_cmd));

    _currentHMILevel = SDLHMILevelNone;

    [self.transactionQueue cancelAllOperations];
    self.transactionQueue = [self sdl_newTransactionQueue];
    _preloadedChoices = [NSMutableSet set];

    _vrOptional = YES;
    _nextChoiceId = ChoiceCellIdMin;
    _nextCancelId = ChoiceCellCancelIdMin;
}

- (void)didEnterStateCheckingVoiceOptional {
    // Setup by sending a Choice Set without VR, seeing if there's an error. If there is, send one with VR. This choice set will be used for `presentKeyboard` interactions.
    __weak typeof(self) weakself = self;
    SDLCheckChoiceVROptionalOperation *checkOp = [[SDLCheckChoiceVROptionalOperation alloc] initWithConnectionManager:self.connectionManager completionHandler:^(BOOL isVROptional, NSError * _Nullable error) {
        __strong typeof(weakself) strongself = weakself;
        if ([self.currentState isEqualToString:SDLChoiceManagerStateShutdown]) { return; }

        strongself.isVROptional = isVROptional;
        if (weakOp.error != nil) {
            [strongself.stateMachine transitionToState:SDLChoiceManagerStateStartupError];
        } else {
            [strongself.stateMachine transitionToState:SDLChoiceManagerStateReady];
        }
    }];

    [self.transactionQueue addOperation:checkOp];
}

- (void)didEnterStateStartupError {
    // TODO
}

#pragma mark - Choice Management

#pragma mark Upload / Delete

- (void)preloadChoices:(NSArray<SDLChoiceCell *> *)choices withCompletionHandler:(nullable SDLPreloadChoiceCompletionHandler)handler {
    SDLLogV(@"Request to preload choices: %@", choices);
    if ([self.currentState isEqualToString:SDLChoiceManagerStateShutdown]) {
        NSError *error = [NSError sdl_choiceSetManager_incorrectState:self.currentState];
        SDLLogE(@"Attempted to preload choices but the choice set manager is shut down: %@", error);
        if (handler != nil) {
            handler(error);
        }
        return;
    }

    NSOrderedSet<SDLChoiceCell *> *choicesToUpload = [NSOrderedSet orderedSetWithArray:choices];
    if (choicesToUpload.count == 0) {
        SDLLogD(@"All choices already preloaded. No need to perform a preload");
        if (handler != nil) {
            handler(nil);
        }

        return;
    }

    // Add ids to all the choices, ones that are already on the head unit will be removed when the preload starts
    [self sdl_updateIdsOnChoices:choicesToUpload];

    // Upload pending preloads
    // For backward compatibility with Gen38Inch display type head units
    SDLLogD(@"Preloading choices");
    SDLLogV(@"Choices to be uploaded: %@", choicesToUpload);
    NSString *displayName = self.systemCapabilityManager.displays.firstObject.displayName;

    __weak typeof(self) weakSelf = self;
    SDLPreloadChoicesOperation *preloadOp = [[SDLPreloadChoicesOperation alloc] initWithConnectionManager:self.connectionManager fileManager:self.fileManager displayName:displayName windowCapability:self.systemCapabilityManager.defaultMainWindowCapability isVROptional:self.isVROptional cellsToPreload:choicesToUpload loadedCells:self.preloadedChoices completionHandler:^(NSSet<SDLChoiceCell *> * _Nonnull updatedLoadedCells, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;

        // Check if the manager has shutdown because the list of uploaded and pending choices should not be updated
        if ([strongSelf.currentState isEqualToString:SDLChoiceManagerStateShutdown]) {
            SDLLogD(@"Cancelling preloading choices because the manager is shut down");
            return;
        }

        // Update the list of `preloadedChoices`
        [SDLGlobals runSyncOnSerialSubQueue:self.readWriteQueue block:^{
            strongSelf.preloadedChoices = updatedLoadedCells;
            [strongSelf sdl_updatePendingTasksWithCurrentPreloads];
        }];

        SDLLogD(@"Choices finished preloading");
        if (handler != nil) {
            if ([weakSelf.currentState isEqualToString:SDLChoiceManagerStateShutdown]) {
                handler([NSError sdl_choiceSetManager_incorrectState:SDLChoiceManagerStateShutdown]);
            } else {
                handler(error);
            }

            return;
        }
    }];

    [self.transactionQueue addOperation:preloadOp];
}

- (void)deleteChoices:(NSArray<SDLChoiceCell *> *)choices {
    SDLLogV(@"Request to delete choices: %@", choices);
    if (![self.currentState isEqualToString:SDLChoiceManagerStateReady]) {
        SDLLogE(@"Attempted to delete choices in an incorrect state: %@, they will not be deleted", self.currentState);
        return;
    }

    __weak typeof(self) weakself = self;
    SDLDeleteChoicesOperation *deleteOp = [[SDLDeleteChoicesOperation alloc] initWithConnectionManager:self.connectionManager cellsToDelete:[NSSet setWithArray:choices] loadedCells:self.preloadedChoices completionHandler:^(NSSet<SDLChoiceCell *> * _Nonnull updatedLoadedCells, NSError *_Nullable error) {
        __strong typeof(weakself) strongself = weakself;
        SDLLogD(@"Finished deleting choices");

        strongself.preloadedChoices = updatedLoadedCells;
        [strongself sdl_updatePendingTasksWithCurrentPreloads];

        if (error != nil) {
            SDLLogE(@"Failed to delete choices with error: %@", error);
        }
    }];

    [self.transactionQueue addOperation:deleteOp];
}

#pragma mark Present

- (void)presentChoiceSet:(SDLChoiceSet *)choiceSet mode:(SDLInteractionMode)mode withKeyboardDelegate:(nullable id<SDLKeyboardDelegate>)delegate {
    if (![self.currentState isEqualToString:SDLChoiceManagerStateReady]) {
        SDLLogE(@"Attempted to present choices in an incorrect state: %@, it will not be presented", self.currentState);
        return;
    }

    if (choiceSet == nil) {
        SDLLogW(@"Attempted to present a nil choice set, ignoring.");
        return;
    }

    SDLLogD(@"Preloading and presenting choice set: %@", choiceSet);

    // Create an operation to preload the choices. We don't check if things are on the head unit and skip this so that if there's a delete operation in progress (etc.) we still ensure everything will be loaded right before the present. We don't check the completion handler because the present operation will take care of figuring out if it can present and returning an error.
    [self preloadChoices:choiceSet.choices withCompletionHandler:nil];

    // Add an operation to present it once the preload is complete
    SDLPresentChoiceSetCompletionHandler presentCompletionHandler = ^void(SDLChoiceCell *_Nullable selectedCell, NSUInteger selectedRow, SDLTriggerSource selectedTriggerSource, NSError *_Nullable error) {
        SDLLogD(@"Finished presenting choice set: %@", choiceSet);

        if (error != nil && delegate != nil) {
            [choiceSet.delegate choiceSet:choiceSet didReceiveError:error];
        } else if (selectedCell != nil && choiceSet.delegate != nil) {
            [choiceSet.delegate choiceSet:choiceSet didSelectChoice:selectedCell withSource:selectedTriggerSource atRowIndex:selectedRow];
        }
    };

    SDLPresentChoiceSetOperation *presentOp = nil;
    if (delegate == nil) {
        // Non-searchable choice set
        presentOp = [[SDLPresentChoiceSetOperation alloc] initWithConnectionManager:self.connectionManager choiceSet:choiceSet mode:mode keyboardProperties:nil keyboardDelegate:nil cancelID:self.nextCancelId windowCapability:self.currentWindowCapability loadedCells:self.preloadedChoices completionHandler:presentCompletionHandler];
    } else {
        // Searchable choice set
        presentOp = [[SDLPresentChoiceSetOperation alloc] initWithConnectionManager:self.connectionManager choiceSet:choiceSet mode:mode keyboardProperties:self.keyboardConfiguration keyboardDelegate:delegate cancelID:self.nextCancelId windowCapability:self.currentWindowCapability loadedCells:self.preloadedChoices completionHandler:presentCompletionHandler];
    }

    [self.transactionQueue addOperation:presentOp];
}

- (nullable NSNumber<SDLInt> *)presentKeyboardWithInitialText:(NSString *)initialText delegate:(id<SDLKeyboardDelegate>)delegate {
    if (![self.currentState isEqualToString:SDLChoiceManagerStateReady]) {
        SDLLogE(@"Attempted to present keyboard in an incorrect state: %@, it will not be presented", self.currentState);
        return nil;
    }

    SDLLogD(@"Presenting keyboard with initial text: %@", initialText);
    // Present a keyboard with the choice set that we used to test VR's optional state
    UInt16 keyboardCancelId = self.nextCancelId;
    SDLPresentKeyboardOperation *keyboardOperation = [[SDLPresentKeyboardOperation alloc] initWithConnectionManager:self.connectionManager keyboardProperties:self.keyboardConfiguration initialText:initialText keyboardDelegate:delegate cancelID:keyboardCancelId windowCapability:self.currentWindowCapability];
    [self.transactionQueue addOperation:keyboardOperation];
    return @(keyboardCancelId);
}

- (void)dismissKeyboardWithCancelID:(NSNumber<SDLInt> *)cancelID {
    for (SDLAsynchronousOperation *op in self.transactionQueue.operations) {
        if (![op isKindOfClass:SDLPresentKeyboardOperation.class]) { continue; }

        SDLPresentKeyboardOperation *keyboardOperation = (SDLPresentKeyboardOperation *)op;
        if (keyboardOperation.cancelId != cancelID.unsignedShortValue) { continue; }

        SDLLogD(@"Dismissing keyboard with cancel ID: %@", cancelID);
        [keyboardOperation dismissKeyboard];
        break;
    }
}

#pragma mark - Choice Management Helpers

- (void)sdl_updatePendingTasksWithCurrentPreloads {
    for (NSOperation *op in self.transactionQueue.operations) {
        if (op.isExecuting || op.isCancelled) { continue; }

        if ([op isMemberOfClass:SDLPreloadChoicesOperation.class]) {
            SDLPreloadChoicesOperation *preloadOp = (SDLPreloadChoicesOperation *)op;
            preloadOp.loadedCells = self.preloadedChoices;
        } else if ([op isMemberOfClass:SDLPresentChoiceSetOperation.class]) {
            SDLPresentChoiceSetOperation *presentOp = (SDLPresentChoiceSetOperation *)op;
            presentOp.loadedCells = self.preloadedChoices;
        } else if ([op isMemberOfClass:SDLDeleteChoicesOperation.class]) {
            SDLDeleteChoicesOperation *deleteOp = (SDLDeleteChoicesOperation *)op;
            deleteOp.loadedCells = self.preloadedChoices;
        }
    }
}

/// Checks the passed list of choices to be uploaded and returns the items that have not yet been uploaded to the module.
/// @param choices The choices to be uploaded
/// @return The choices that have not yet been uploaded to the module
- (NSMutableOrderedSet<SDLChoiceCell *> *)sdl_choicesToBeUploadedWithArray:(NSArray<SDLChoiceCell *> *)choices {
    NSMutableOrderedSet<SDLChoiceCell *> *choicesCopy = [[NSMutableOrderedSet alloc] initWithArray:choices copyItems:YES];

    SDLVersion *choiceUniquenessSupportedVersion = [[SDLVersion alloc] initWithMajor:7 minor:1 patch:0];
    if ([[SDLGlobals sharedGlobals].rpcVersion isLessThanVersion:choiceUniquenessSupportedVersion]) {
        // If we're on < RPC 7.1, all primary texts need to be unique, so we don't need to check removed properties and duplicate cells
        [self sdl_addUniqueNamesToCells:choicesCopy];
    } else {
        // On > RPC 7.1, at this point all cells are unique when considering all properties, but we also need to check if any cells will _appear_ as duplicates when displayed on the screen. To check that, we'll remove properties from the set cells based on the system capabilities (we probably don't need to consider them changing between now and when they're actually sent to the HU) and check for uniqueness again. Then we'll add unique identifiers to primary text if there are duplicates. Then we transfer the primary text identifiers back to the main cells and add those to an operation to be sent.
        NSMutableOrderedSet<SDLChoiceCell *> *strippedCellsCopy = [self sdl_removeUnusedProperties:choicesCopy];
        [self sdl_addUniqueNamesBasedOnStrippedCells:strippedCellsCopy toUnstrippedCells:choicesCopy];
    }
    [choicesCopy minusSet:self.preloadedChoices];

    return choicesCopy;
}

- (NSMutableOrderedSet<SDLChoiceCell *> *)sdl_removeUnusedProperties:(NSMutableOrderedSet<SDLChoiceCell *> *)choiceCells {
    NSMutableOrderedSet<SDLChoiceCell *> *strippedCellsCopy = [[NSMutableOrderedSet alloc] initWithOrderedSet:choiceCells copyItems:YES];
    for (SDLChoiceCell *cell in strippedCellsCopy) {
        // Strip away fields that cannot be used to determine uniqueness visually including fields not supported by the HMI
        cell.voiceCommands = nil;

        // Don't check SDLImageFieldNameSubMenuIcon because it was added in 7.0 when the feature was added in 5.0. Just assume that if CommandIcon is not available, the submenu icon is not either.
        if (![self.currentWindowCapability hasImageFieldOfName:SDLImageFieldNameChoiceImage]) {
            cell.artwork = nil;
        }
        if (![self.currentWindowCapability hasTextFieldOfName:SDLTextFieldNameSecondaryText]) {
            cell.secondaryText = nil;
        }
        if (![self.currentWindowCapability hasTextFieldOfName:SDLTextFieldNameTertiaryText]) {
            cell.tertiaryText = nil;
        }
        if (![self.currentWindowCapability hasImageFieldOfName:SDLImageFieldNameChoiceSecondaryImage]) {
            cell.secondaryArtwork = nil;
        }
    }

    return strippedCellsCopy;
}

- (void)sdl_addUniqueNamesBasedOnStrippedCells:(NSMutableOrderedSet<SDLChoiceCell *> *)strippedCells toUnstrippedCells:(NSMutableOrderedSet<SDLChoiceCell *> *)unstrippedCells {
    NSParameterAssert(strippedCells.count == unstrippedCells.count);
    // Tracks how many of each cell primary text there are so that we can append numbers to make each unique as necessary
    NSMutableDictionary<SDLChoiceCell *, NSNumber *> *dictCounter = [[NSMutableDictionary alloc] init];
    for (NSUInteger i = 0; i < strippedCells.count; i++) {
        SDLChoiceCell *cell = strippedCells[i];
        NSNumber *counter = dictCounter[cell];
        if (counter != nil) {
            counter = @(counter.intValue + 1);
            dictCounter[cell] = counter;
        } else {
            dictCounter[cell] = @1;
        }

        counter = dictCounter[cell];
        if (counter.intValue > 1) {
            unstrippedCells[i].uniqueText = [NSString stringWithFormat: @"%@ (%d)", unstrippedCells[i].text, counter.intValue];
        }
    }
}

/// Checks if 2 or more cells have the same text/title. In case this condition is true, this function will handle the presented issue by adding "(count)".
/// E.g. Choices param contains 2 cells with text/title "Address" will be handled by updating the uniqueText/uniqueTitle of the second cell to "Address (2)".
/// @param choices The choices to be uploaded.
- (void)sdl_addUniqueNamesToCells:(NSOrderedSet<SDLChoiceCell *> *)choices {
    // Tracks how many of each cell primary text there are so that we can append numbers to make each unique as necessary
    NSMutableDictionary<NSString *, NSNumber *> *dictCounter = [[NSMutableDictionary alloc] init];
    for (SDLChoiceCell *cell in choices) {
        NSString *cellName = cell.text;
        NSNumber *counter = dictCounter[cellName];
        if (counter != nil) {
            counter = @(counter.intValue + 1);
            dictCounter[cellName] = counter;
        } else {
            dictCounter[cellName] = @1;
        }
        if (counter.intValue > 1) {
            cell.uniqueText = [NSString stringWithFormat: @"%@ (%d)", cell.text, counter.intValue];
        }
    }
}

/// Assigns a unique id to each choice item.
/// @param choices An array of choices
- (void)sdl_updateIdsOnChoices:(NSOrderedSet<SDLChoiceCell *> *)choices {
    for (SDLChoiceCell *cell in choices) {
        cell.choiceId = self.nextChoiceId;
    }
}

#pragma mark - Keyboard Configuration

- (void)setKeyboardConfiguration:(nullable SDLKeyboardProperties *)keyboardConfiguration {
    if (keyboardConfiguration == nil) {
        SDLLogD(@"Updating keyboard configuration to the default");
        _keyboardConfiguration = [self sdl_defaultKeyboardConfiguration];
    } else {
        SDLLogD(@"Updating keyboard configuration to a new configuration: %@", keyboardConfiguration);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        _keyboardConfiguration = [[SDLKeyboardProperties alloc] initWithLanguage:keyboardConfiguration.language layout:keyboardConfiguration.keyboardLayout keypressMode:SDLKeypressModeResendCurrentEntry limitedCharacterList:keyboardConfiguration.limitedCharacterList autoCompleteText:keyboardConfiguration.autoCompleteText autoCompleteList:keyboardConfiguration.autoCompleteList];
#pragma clang diagnostic pop

        if (keyboardConfiguration.keypressMode != SDLKeypressModeResendCurrentEntry) {
            SDLLogW(@"Attempted to set a keyboard configuration with an invalid keypress mode; only .resentCurrentEntry is valid. This value will be ignored, the rest of the properties will be set.");
        }
    }
}

- (SDLKeyboardProperties *)sdl_defaultKeyboardConfiguration {
    return [[SDLKeyboardProperties alloc] initWithLanguage:SDLLanguageEnUs keyboardLayout:SDLKeyboardLayoutQWERTY keypressMode:SDLKeypressModeResendCurrentEntry limitedCharacterList:nil autoCompleteList:nil maskInputCharacters:nil customKeys:nil];
}

#pragma mark - Getters

- (UInt16)nextChoiceId {
    __block UInt16 choiceId = 0;
    [SDLGlobals runSyncOnSerialSubQueue:self.readWriteQueue block:^{
        choiceId = self->_nextChoiceId;
        self->_nextChoiceId = choiceId + 1;
    }];

    return choiceId;
}

- (UInt16)nextCancelId {
    __block UInt16 cancelId = 0;
    [SDLGlobals runSyncOnSerialSubQueue:self.readWriteQueue block:^{
        cancelId = self->_nextCancelId;
        if (cancelId >= ChoiceCellCancelIdMax) {
            self->_nextCancelId = ChoiceCellCancelIdMin;
        } else {
            self->_nextCancelId = cancelId + 1;
        }
    }];

    return cancelId;
}

- (NSString *)currentState {
    return self.stateMachine.currentState;
}

#pragma mark - RPC Responses / Notifications

- (void)sdl_displayCapabilityDidUpdate {
    self.currentWindowCapability = self.systemCapabilityManager.defaultMainWindowCapability;
    [self sdl_updateTransactionQueueSuspended];
}

- (void)sdl_hmiStatusNotification:(SDLRPCNotificationNotification *)notification {
    // We can only present a choice set if we're in FULL
    SDLOnHMIStatus *hmiStatus = (SDLOnHMIStatus *)notification.notification;
    if (hmiStatus.windowID != nil && hmiStatus.windowID.integerValue != SDLPredefinedWindowsDefaultWindow) { return; }

    self.currentHMILevel = hmiStatus.hmiLevel;

    [self sdl_updateTransactionQueueSuspended];
}

@end

NS_ASSUME_NONNULL_END
