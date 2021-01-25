//
//  SDLMenuReplaceDynamicOperation.m
//  SmartDeviceLink
//
//  Created by Joel Fischer on 1/20/21.
//  Copyright © 2021 smartdevicelink. All rights reserved.
//

#import "SDLMenuReplaceDynamicOperation.h"

#import "SDLArtwork.h"
#import "SDLConnectionManagerType.h"
#import "SDLDynamicMenuUpdateAlgorithm.h"
#import "SDLDynamicMenuUpdateRunScore.h"
#import "SDLError.h"
#import "SDLFileManager.h"
#import "SDLLogMacros.h"
#import "SDLMenuCell.h"
#import "SDLMenuConfiguration.h"
#import "SDLMenuReplaceUtilities.h"
#import "SDLTextFieldName.h"
#import "SDLWindowCapability.h"
#import "SDLWindowCapability+ScreenManagerExtensions.h"

@interface SDLMenuReplaceDynamicOperation ()

@property (weak, nonatomic) id<SDLConnectionManagerType> connectionManager;
@property (weak, nonatomic) SDLFileManager *fileManager;
@property (strong, nonatomic) NSArray<SDLMenuCell *> *currentMenu;
@property (strong, nonatomic) NSArray<SDLMenuCell *> *updatedMenu;

@property (copy, nonatomic, nullable) NSError *internalError;

@end

@implementation SDLMenuReplaceDynamicOperation

- (instancetype)initWithConnectionManager:(id<SDLConnectionManagerType>)connectionManager fileManager:(SDLFileManager *)fileManager windowCapability:(SDLWindowCapability *)windowCapability menuConfiguration:(SDLMenuConfiguration *)menuConfiguration currentMenu:(NSArray<SDLMenuCell *> *)currentMenu updatedMenu:(NSArray<SDLMenuCell *> *)updatedMenu {
    self = [super init];
    if (!self) { return nil; }

    _connectionManager = connectionManager;
    _fileManager = fileManager;
    _windowCapability = windowCapability;
    _menuConfiguration = menuConfiguration;
    _currentMenu = currentMenu;
    _updatedMenu = updatedMenu;

    return self;
}

- (void)start {
    [super start];
    if (self.isCancelled) {
        [self finishOperation];
        return;
    }

    SDLDynamicMenuUpdateRunScore *runScore = [SDLDynamicMenuUpdateAlgorithm compareOldMenuCells:self.currentMenu updatedMenuCells:self.updatedMenu];
    NSArray<NSNumber *> *deleteMenuStatus = runScore.oldStatus;
    NSArray<NSNumber *> *addMenuStatus = runScore.updatedStatus;

    NSArray<SDLMenuCell *> *cellsToDelete = [self sdl_filterDeleteMenuItemsWithOldMenuItems:self.currentMenu basedOnStatusList:deleteMenuStatus];
    NSArray<SDLMenuCell *> *cellsToAdd = [self sdl_filterAddMenuItemsWithNewMenuItems:self.updatedMenu basedOnStatusList:addMenuStatus];
    // These arrays should ONLY contain KEEPS. These will be used for SubMenu compares
    NSArray<SDLMenuCell *> *oldKeeps = [self sdl_filterKeepMenuItemsWithOldMenuItems:self.currentMenu basedOnStatusList:deleteMenuStatus];
    NSArray<SDLMenuCell *> *newKeeps = [self sdl_filterKeepMenuItemsWithNewMenuItems:self.updatedMenu basedOnStatusList:addMenuStatus];

    // Cells that will be added need new ids
    [self sdl_updateIdsOnMenuCells:cellsToAdd parentId:ParentIdNotFound];

    // Since we are creating a new Menu but keeping old cells we must firt transfer the old cellIDs to the new menus kept cells.
    [self transferCellIDFromOldCells:oldKeeps toKeptCells:newKeeps];

    // TODO: We don't check cancellation or finish
    NSArray<SDLArtwork *> *artworksToBeUploaded = [SDLMenuReplaceUtilities findAllArtworksToBeUploadedFromCells:self.updatedMenu fileManager:self.fileManager windowCapability:self.windowCapability];
    if (artworksToBeUploaded.count > 0) {
        [self.fileManager uploadArtworks:artworksToBeUploaded completionHandler:^(NSArray<NSString *> * _Nonnull artworkNames, NSError * _Nullable error) {
            if (error != nil) {
                SDLLogE(@"Error uploading menu artworks: %@", error);
            }

            SDLLogD(@"Menu artworks uploaded");
            __weak typeof(self) weakself = self;
            [self sdl_updateMenuWithCellsToDelete:cellsToDelete cellsToAdd:cellsToAdd completionHandler:^(NSError * _Nullable error) {
                [weakself sdl_startSubMenuUpdatesWithOldKeptCells:oldKeeps newKeptCells:newKeeps atIndex:0];
            }];
        }];
    } else {
        // Cells have no artwork to load
        __weak typeof(self) weakself = self;
        [self sdl_updateMenuWithCellsToDelete:cellsToDelete cellsToAdd:cellsToAdd completionHandler:^(NSError * _Nullable error) {
            [weakself sdl_startSubMenuUpdatesWithOldKeptCells:oldKeeps newKeptCells:newKeeps atIndex:0];
        }];
    }
}

#pragma mark Dynamic Menu Helpers

- (void)sdl_startSubMenuUpdatesWithOldKeptCells:(NSArray<SDLMenuCell *> *)oldKeptCells newKeptCells:(NSArray<SDLMenuCell *> *)newKeptCells atIndex:(NSUInteger)startIndex {
    if (oldKeptCells.count == 0 || startIndex >= oldKeptCells.count) { return; }

    if (oldKeptCells[startIndex].subCells.count > 0) {
        SDLDynamicMenuUpdateRunScore *tempScore = [SDLDynamicMenuUpdateAlgorithm compareOldMenuCells:oldKeptCells[startIndex].subCells updatedMenuCells:newKeptCells[startIndex].subCells];
        NSArray<NSNumber *> *deleteMenuStatus = tempScore.oldStatus;
        NSArray<NSNumber *> *addMenuStatus = tempScore.updatedStatus;

        NSArray<SDLMenuCell *> *cellsToDelete = [self sdl_filterDeleteMenuItemsWithOldMenuItems:oldKeptCells[startIndex].subCells basedOnStatusList:deleteMenuStatus];
        NSArray<SDLMenuCell *> *cellsToAdd = [self sdl_filterAddMenuItemsWithNewMenuItems:newKeptCells[startIndex].subCells basedOnStatusList:addMenuStatus];

        NSArray<SDLMenuCell *> *oldKeeps = [self sdl_filterKeepMenuItemsWithOldMenuItems:oldKeptCells[startIndex].subCells basedOnStatusList:deleteMenuStatus];
        NSArray<SDLMenuCell *> *newKeeps = [self sdl_filterKeepMenuItemsWithNewMenuItems:newKeptCells[startIndex].subCells basedOnStatusList:addMenuStatus];

        [self sdl_updateIdsOnMenuCells:cellsToAdd parentId:newKeptCells[startIndex].cellId];
        [self transferCellIDFromOldCells:oldKeeps toKeptCells:newKeeps];

        __weak typeof(self) weakself = self;
        [self sdl_sendDeleteCurrentMenu:cellsToDelete withCompletionHandler:^(NSError * _Nullable error) {
            [weakself sdl_sendUpdatedMenu:cellsToAdd usingMenu:weakself.menuCells[startIndex].subCells withCompletionHandler:^(NSError * _Nullable error) {
                // After the first set of submenu cells were added and deleted we must find the next set of subcells untll we loop through all the elemetns
                [weakself sdl_startSubMenuUpdatesWithOldKeptCells:oldKeptCells newKeptCells:newKeptCells atIndex:(startIndex + 1)];
            }];
        }];
    } else {
        // After the first set of submenu cells were added and deleted we must find the next set of subcells untll we loop through all the elemetns
        [self sdl_startSubMenuUpdatesWithOldKeptCells:oldKeptCells newKeptCells:newKeptCells atIndex:(startIndex + 1)];
    }
}

- (NSArray<SDLMenuCell *> *)sdl_filterDeleteMenuItemsWithOldMenuItems:(NSArray<SDLMenuCell *> *)oldMenuCells basedOnStatusList:(NSArray<NSNumber *> *)oldStatusList {
    NSMutableArray<SDLMenuCell *> *deleteCells = [[NSMutableArray alloc] init];
    // The index of the status should corrleate 1-1 with the number of items in the menu
    // [2,0,2,0] => [A,B,C,D] = [B,D]
    for (NSUInteger index = 0; index < oldStatusList.count; index++) {
        if (oldStatusList[index].integerValue == MenuCellStateDelete) {
            [deleteCells addObject:oldMenuCells[index]];
        }
    }
    return [deleteCells copy];
}

- (NSArray<SDLMenuCell *> *)sdl_filterAddMenuItemsWithNewMenuItems:(NSArray<SDLMenuCell *> *)newMenuCells basedOnStatusList:(NSArray<NSNumber *> *)newStatusList {
    NSMutableArray<SDLMenuCell *> *addCells = [[NSMutableArray alloc] init];
    // The index of the status should corrleate 1-1 with the number of items in the menu
    // [2,1,2,1] => [A,B,C,D] = [B,D]
    for (NSUInteger index = 0; index < newStatusList.count; index++) {
        if (newStatusList[index].integerValue == MenuCellStateAdd) {
            [addCells addObject:newMenuCells[index]];
        }
    }
    return [addCells copy];
}

- (NSArray<SDLMenuCell *> *)sdl_filterKeepMenuItemsWithOldMenuItems:(NSArray<SDLMenuCell *> *)oldMenuCells basedOnStatusList:(NSArray<NSNumber *> *)keepStatusList {
    NSMutableArray<SDLMenuCell *> *keepMenuCells = [[NSMutableArray alloc] init];

    for (NSUInteger index = 0; index < keepStatusList.count; index++) {
        if (keepStatusList[index].integerValue == MenuCellStateKeep) {
            [keepMenuCells addObject:oldMenuCells[index]];
        }
    }
    return [keepMenuCells copy];
}

- (NSArray<SDLMenuCell *> *)sdl_filterKeepMenuItemsWithNewMenuItems:(NSArray<SDLMenuCell *> *)newMenuCells basedOnStatusList:(NSArray<NSNumber *> *)keepStatusList {
    NSMutableArray<SDLMenuCell *> *keepMenuCells = [[NSMutableArray alloc] init];
    for (NSUInteger index = 0; index < keepStatusList.count; index++) {
        if (keepStatusList[index].integerValue == MenuCellStateKeep) {
            [keepMenuCells addObject:newMenuCells[index]];
        }
    }
    return [keepMenuCells copy];
}

- (void)transferCellIDFromOldCells:(NSArray<SDLMenuCell *> *)oldCells toKeptCells:(NSArray<SDLMenuCell *> *)newCells {
    if (oldCells.count == 0) { return; }
    for (NSUInteger i = 0; i < newCells.count; i++) {
        newCells[i].cellId = oldCells[i].cellId;
    }
}

@end
