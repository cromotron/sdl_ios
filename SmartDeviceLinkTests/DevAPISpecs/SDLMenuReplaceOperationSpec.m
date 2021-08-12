//
//  SDLMenuReplaceOperationSpec.m
//  SmartDeviceLinkTests
//
//  Created by Joel Fischer on 2/16/21.
//  Copyright © 2021 smartdevicelink. All rights reserved.
//

#import <Nimble/Nimble.h>
#import <OCMock/OCMock.h>
#import <Quick/Quick.h>

#import <SmartDeviceLink/SmartDeviceLink.h>
#import "SDLGlobals.h"
#import "SDLMenuReplaceOperation.h"
#import "SDLMenuManagerPrivateConstants.h"
#import "SDLMenuReplaceUtilities.h"
#import "TestConnectionManager.h"

@interface SDLMenuCell ()

@property (assign, nonatomic) UInt32 parentCellId;
@property (assign, nonatomic) UInt32 cellId;

@end

QuickSpecBegin(SDLMenuReplaceOperationSpec)

describe(@"a menu replace operation", ^{
    __block SDLMenuReplaceOperation *testOp = nil;

    __block TestConnectionManager *testConnectionManager = nil;
    __block SDLFileManager *testFileManager = nil;
    __block SDLWindowCapability *testWindowCapability = nil;
    __block SDLMenuConfiguration *testMenuConfiguration = nil;
    __block NSArray<SDLMenuCell *> *testCurrentMenu = nil;
    __block NSArray<SDLMenuCell *> *testNewMenu = nil;

    __block SDLArtwork *testArtwork = nil;
    __block SDLArtwork *testArtwork2 = nil;
    __block SDLArtwork *testArtwork3 = nil;

    __block SDLMenuCell *textOnlyCell = nil;
    __block SDLMenuCell *textOnlyCell2 = nil;
    __block SDLMenuCell *textAndImageCell = nil;
    __block SDLMenuCell *submenuCell = nil;
    __block SDLMenuCell *submenuImageCell = nil;

    __block SDLAddCommandResponse *addCommandSuccessResponse = nil;
    __block SDLAddSubMenuResponse *addSubMenuSuccessResponse = nil;
    __block SDLDeleteCommandResponse *deleteCommandSuccessResponse = nil;
    __block SDLDeleteSubMenuResponse *deleteSubMenuSuccessResponse = nil;

    __block NSArray<SDLMenuCell *> *resultMenuCells = nil;
    __block NSError *resultError = nil;
    __block SDLCurrentMenuUpdatedBlock testCurrentMenuUpdatedBlock = nil;

    __block SDLMenuReplaceUtilities *mockReplaceUtilities = nil;

    beforeEach(^{
        [SDLGlobals sharedGlobals].rpcVersion = [SDLVersion versionWithMajor:7 minor:1 patch:0];

        testArtwork = [[SDLArtwork alloc] initWithData:[@"Test data" dataUsingEncoding:NSUTF8StringEncoding] name:@"some artwork name" fileExtension:@"png" persistent:NO];
        testArtwork2 = [[SDLArtwork alloc] initWithData:[@"Test data 2" dataUsingEncoding:NSUTF8StringEncoding] name:@"some artwork name 2" fileExtension:@"png" persistent:NO];
        testArtwork3 = [[SDLArtwork alloc] initWithData:[@"Test data 3" dataUsingEncoding:NSUTF8StringEncoding] name:@"some artwork name" fileExtension:@"png" persistent:NO];
        testArtwork3.overwrite = YES;

        textOnlyCell = [[SDLMenuCell alloc] initWithTitle:@"Test 1" secondaryText:nil tertiaryText:nil icon:nil secondaryArtwork:nil voiceCommands:nil handler:^(SDLTriggerSource  _Nonnull triggerSource) {}];
        textOnlyCell2 = [[SDLMenuCell alloc] initWithTitle:@"Test 5" secondaryText:nil tertiaryText:nil icon:nil secondaryArtwork:nil voiceCommands:nil handler:^(SDLTriggerSource  _Nonnull triggerSource) {}];
        textAndImageCell = [[SDLMenuCell alloc] initWithTitle:@"Test 2" secondaryText:nil tertiaryText:nil icon:testArtwork secondaryArtwork:nil voiceCommands:nil handler:^(SDLTriggerSource  _Nonnull triggerSource) {}];
        submenuCell = [[SDLMenuCell alloc] initWithTitle:@"Test 3" secondaryText:nil tertiaryText:nil icon:nil secondaryArtwork:nil submenuLayout:nil subCells:@[textOnlyCell, textAndImageCell]];
        submenuImageCell = [[SDLMenuCell alloc] initWithTitle:@"Test 4" secondaryText:nil tertiaryText:nil icon:testArtwork2 secondaryArtwork:nil submenuLayout:SDLMenuLayoutTiles subCells:@[textOnlyCell]];

        addCommandSuccessResponse = [[SDLAddCommandResponse alloc] init];
        addCommandSuccessResponse.success = @YES;
        addCommandSuccessResponse.resultCode = SDLResultSuccess;
        addSubMenuSuccessResponse = [[SDLAddSubMenuResponse alloc] init];
        addSubMenuSuccessResponse.success = @YES;
        addSubMenuSuccessResponse.resultCode = SDLResultSuccess;
        deleteCommandSuccessResponse = [[SDLDeleteCommandResponse alloc] init];
        deleteCommandSuccessResponse.success = @YES;
        deleteCommandSuccessResponse.resultCode = SDLResultSuccess;
        deleteSubMenuSuccessResponse = [[SDLDeleteSubMenuResponse alloc] init];
        deleteSubMenuSuccessResponse.success = @YES;
        deleteSubMenuSuccessResponse.resultCode = SDLResultSuccess;

        testOp = nil;
        testConnectionManager = [[TestConnectionManager alloc] init];
        testFileManager = OCMClassMock([SDLFileManager class]);

        SDLImageField *commandImageField = [[SDLImageField alloc] initWithName:SDLImageFieldNameCommandIcon imageTypeSupported:@[SDLFileTypePNG] imageResolution:nil];
        SDLImageField *submenuImageField = [[SDLImageField alloc] initWithName:SDLImageFieldNameSubMenuIcon imageTypeSupported:@[SDLFileTypePNG] imageResolution:nil];
        testWindowCapability = [[SDLWindowCapability alloc] initWithWindowID:@0 textFields:nil imageFields:@[commandImageField, submenuImageField] imageTypeSupported:nil templatesAvailable:nil numCustomPresetsAvailable:nil buttonCapabilities:nil softButtonCapabilities:nil menuLayoutsAvailable:nil dynamicUpdateCapabilities:nil keyboardCapabilities:nil];
        testMenuConfiguration = [[SDLMenuConfiguration alloc] initWithMainMenuLayout:SDLMenuLayoutList defaultSubmenuLayout:SDLMenuLayoutList];
        testCurrentMenu = @[];
        testNewMenu = nil;

        resultMenuCells = nil;
        resultError = nil;
        testCurrentMenuUpdatedBlock = ^(NSArray<SDLMenuCell *> *currentMenuCells, NSError *error) {
            resultMenuCells = currentMenuCells;
            resultError = error;
        };

        mockReplaceUtilities = OCMClassMock([SDLMenuReplaceUtilities class]);
    });

    describe(@"sending initial batch of cells", ^{
        context(@"when setting no cells", ^{
            it(@"should finish without doing anything", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                expect(testConnectionManager.receivedRequests).to(beEmpty());
                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(beEmpty());
            });
        });

        context(@"when starting while cancelled", ^{
            it(@"should finish without doing anything", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp cancel];
                [testOp start];

                expect(testConnectionManager.receivedRequests).to(beEmpty());
                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(beNil());
            });
        });

        context(@"when uploading a text-only cell", ^{
            beforeEach(^{
                testNewMenu = @[textOnlyCell];
                OCMStub([testFileManager fileNeedsUpload:[OCMArg any]]).andReturn(NO);
            });

            it(@"should properly send the RPCs and finish the operation", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                OCMReject([testFileManager uploadArtworks:[OCMArg any] progressHandler:[OCMArg any] completionHandler:[OCMArg any]]);

                NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLDeleteCommand class]];
                NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];
                expect(deletes).to(beEmpty());

                NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddCommand class]];
                NSArray *add = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];
                expect(add).to(haveCount(1));

                [testConnectionManager respondToLastRequestWithResponse:addCommandSuccessResponse];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(haveCount(1));
            });
        });

        context(@"when uploading text and image cell", ^{
            beforeEach(^{
                testNewMenu = @[textAndImageCell];

                OCMStub([testFileManager uploadArtworks:[OCMArg any] progressHandler:([OCMArg invokeBlockWithArgs:textAndImageCell.icon.name, @1.0, [NSNull null], nil]) completionHandler:([OCMArg invokeBlockWithArgs: @[textAndImageCell.icon.name], [NSNull null], nil])]);
            });

            // when the image is already on the head unit
            context(@"when the image is already on the head unit", ^{
                beforeEach(^{
                    OCMStub([testFileManager hasUploadedFile:[OCMArg isNotNil]]).andReturn(YES);
                    OCMStub([testFileManager fileNeedsUpload:[OCMArg isNotNil]]).andReturn(NO);
                });

                it(@"should properly update an image cell", ^{
                    OCMReject([testFileManager uploadArtworks:[OCMArg any] progressHandler:[OCMArg any] completionHandler:[OCMArg any]]);


                    testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                    [testOp start];

                    NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddCommand class]];
                    NSArray *add = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];
                    SDLAddCommand *sentCommand = add.firstObject;

                    expect(add).to(haveCount(1));
                    expect(sentCommand.cmdIcon.value).to(equal(testArtwork.name));

                    [testConnectionManager respondToLastRequestWithResponse:addCommandSuccessResponse];
                    [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                    expect(testOp.isFinished).to(beTrue());
                    expect(resultError).to(beNil());
                    expect(resultMenuCells).to(haveCount(1));
                });
            });

            // when the image is not on the head unit
            context(@"when the image is not on the head unit", ^{
                beforeEach(^{
                    OCMStub([testFileManager hasUploadedFile:[OCMArg isNotNil]]).andReturn(NO);
                    OCMStub([testFileManager fileNeedsUpload:[OCMArg isNotNil]]).andReturn(YES);
                });

                it(@"should attempt to upload artworks then send the add", ^{
                    testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                    [testOp start];

                    OCMVerify([testFileManager uploadArtworks:[OCMArg any] progressHandler:[OCMArg any] completionHandler:[OCMArg any]]);

                    NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLDeleteCommand class]];
                    NSArray *deletesArray = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];
                    expect(deletesArray).to(beEmpty());

                    NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddCommand class]];
                    NSArray *addsArray = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];
                    expect(addsArray).toNot(beEmpty());

                    [testConnectionManager respondToLastRequestWithResponse:addCommandSuccessResponse];
                    [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                    expect(testOp.isFinished).to(beTrue());
                    expect(resultError).to(beNil());
                    expect(resultMenuCells).to(haveCount(1));
                });
            });
        });

        context(@"when uploading a cell with subcells", ^{
            beforeEach(^{
                testNewMenu = @[submenuCell];
            });

            it(@"should send an appropriate number of AddSubmenu and AddCommandRequests", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                [testConnectionManager respondToLastRequestWithResponse:addSubMenuSuccessResponse];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddCommand class]];
                NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                NSPredicate *submenuCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddSubMenu class]];
                NSArray *submenus = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:submenuCommandPredicate];

                expect(adds).to(haveCount(2));
                expect(submenus).to(haveCount(1));

                [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:1 error:nil];
                [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:2 error:nil];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(haveCount(1));
                expect(resultMenuCells[0].subCells).to(haveCount(2));
            });
        });
    });

    context(@"updating a menu without dynamic updates", ^{
        describe(@"basic cell updates", ^{
            context(@"adding a text cell", ^{
                beforeEach(^{
                    testCurrentMenu = [[NSArray alloc] initWithArray:@[textOnlyCell] copyItems:YES];
                    [SDLMenuReplaceUtilities updateIdsOnMenuCells:testCurrentMenu parentId:ParentIdNotFound];

                    testNewMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textOnlyCell2] copyItems:YES];
                });

                it(@"should send a delete and two adds", ^{
                    testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                    [testOp start];

                    [testConnectionManager respondToLastRequestWithResponse:deleteCommandSuccessResponse];
                    [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                    [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:1 error:nil];
                    [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:2 error:nil];
                    [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                    NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteCommand class]];
                    NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];

                    NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLAddCommand class]];
                    NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                    expect(deletes).to(haveCount(1));
                    expect(adds).to(haveCount(2));

                    expect(testOp.isFinished).to(beTrue());
                    expect(resultError).to(beNil());
                    expect(resultMenuCells).to(haveCount(2));
                    expect(resultMenuCells[0]).to(equal(textOnlyCell));
                    expect(resultMenuCells[1]).to(equal(textOnlyCell2));
                });
            });

            context(@"when all cells remain the same", ^{
                beforeEach(^{
                    testCurrentMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textOnlyCell2, textAndImageCell] copyItems:YES];
                    [SDLMenuReplaceUtilities updateIdsOnMenuCells:testCurrentMenu parentId:ParentIdNotFound];

                    testNewMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textOnlyCell2, textAndImageCell] copyItems:YES];
                });

                it(@"should delete all cells and add the new ones", ^{
                    testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:YES currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                    [testOp start];

                    [testConnectionManager respondToRequestWithResponse:deleteCommandSuccessResponse requestNumber:0 error:nil];
                    [testConnectionManager respondToRequestWithResponse:deleteCommandSuccessResponse requestNumber:1 error:nil];
                    [testConnectionManager respondToRequestWithResponse:deleteCommandSuccessResponse requestNumber:2 error:nil];
                    [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                    [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:3 error:nil];
                    [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:4 error:nil];
                    [testConnectionManager respondToRequestWithResponse:addCommandSuccessResponse requestNumber:5 error:nil];
                    [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                    NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteCommand class]];
                    NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];

                    NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLAddCommand class]];
                    NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                    expect(deletes).to(haveCount(3));
                    expect(adds).to(haveCount(3));

                    expect(testOp.isFinished).to(beTrue());
                    expect(resultError).to(beNil());
                    expect(resultMenuCells).to(haveCount(3));
                });
            });
        });

        describe(@"unique cell updates", ^{
            context(@"with cell uniqueness", ^{
                beforeEach(^{
                    [SDLGlobals sharedGlobals].rpcVersion = [SDLVersion versionWithMajor:7 minor:1 patch:0];
                });

                context(@"when cells have the same name but are unique", ^{

                });

                context(@"when cells are completely identical", ^{
                    beforeEach(^{
                        testCurrentMenu = @[];
                        testNewMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textOnlyCell] copyItems:YES];
                    });
                });

                context(@"when cells are unique but are identical when stripped", ^{

                });
            });

            context(@"without cell uniqueness", ^{
                beforeEach(^{
                    [SDLGlobals sharedGlobals].rpcVersion = [SDLVersion versionWithMajor:7 minor:0 patch:0];
                });

                context(@"when cells have the same name but are unique", ^{

                });

                context(@"when cells are completely identical", ^{

                });

                context(@"when cells are unique but are identical when stripped", ^{

                });
            });
        });
    });

    context(@"updating a menu with dynamic updates", ^{
        context(@"adding a text cell", ^{
            beforeEach(^{
                testCurrentMenu = @[textOnlyCell];
                testNewMenu = @[textOnlyCell, textOnlyCell2];
            });

            it(@"should only send an add", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:NO currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteCommand class]];
                NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];

                NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLAddCommand class]];
                NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                expect(deletes).to(haveCount(0));
                expect(adds).to(haveCount(1));

                [testConnectionManager respondToLastRequestWithResponse:addCommandSuccessResponse];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(haveCount(2));
            });
        });

        context(@"rearranging cells with subcells", ^{
            beforeEach(^{
                testCurrentMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, submenuCell, submenuImageCell] copyItems:YES];
                [SDLMenuReplaceUtilities updateIdsOnMenuCells:testCurrentMenu parentId:ParentIdNotFound];

                testNewMenu = [[NSArray alloc] initWithArray:@[submenuCell, submenuImageCell, textOnlyCell] copyItems:YES];

                OCMStub([testFileManager uploadArtworks:[OCMArg any] progressHandler:([OCMArg invokeBlockWithArgs:textAndImageCell.icon.name, @1.0, [NSNull null], nil]) completionHandler:([OCMArg invokeBlockWithArgs: @[textAndImageCell.icon.name], [NSNull null], nil])]);
            });

            it(@"should send dynamic deletes first then dynamic adds case with 2 submenu cells", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:NO currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                // Delete textOnlyCell
                [testConnectionManager respondToLastRequestWithResponse:deleteCommandSuccessResponse];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];
                expect(testOp.currentMenu).toNot(contain(textOnlyCell));

                // Add textOnlyCell
                [testConnectionManager respondToLastRequestWithResponse:addCommandSuccessResponse];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];

                NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteCommand class]];
                NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];

                NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLAddCommand class]];
                NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                NSPredicate *addSubmenuPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddSubMenu class]];
                NSArray *submenu = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addSubmenuPredicate];

                expect(deletes).to(haveCount(1));
                expect(adds).to(haveCount(1));
                expect(submenu).to(haveCount(0));

                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(haveCount(3));
            });
        });

        context(@"removing a cell with subcells", ^{
            beforeEach(^{
                testCurrentMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textAndImageCell, submenuCell, submenuImageCell] copyItems:YES];
                [SDLMenuReplaceUtilities updateIdsOnMenuCells:testCurrentMenu parentId:ParentIdNotFound];

                testNewMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textAndImageCell, submenuCell] copyItems:YES];

                OCMStub([testFileManager uploadArtworks:[OCMArg any] progressHandler:([OCMArg invokeBlockWithArgs:textAndImageCell.icon.name, @1.0, [NSNull null], nil]) completionHandler:([OCMArg invokeBlockWithArgs: @[textAndImageCell.icon.name], [NSNull null], nil])]);
            });

            it(@"should send one deletion", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:NO currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                // Delete submenuImageCell
                [testConnectionManager respondToLastRequestWithResponse:deleteSubMenuSuccessResponse];
                [testConnectionManager respondToLastMultipleRequestsWithSuccess:YES];
                expect(testOp.currentMenu).toNot(contain(submenuImageCell));

                NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteCommand class]];
                NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];

                NSPredicate *deleteSubCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteSubMenu class]];
                NSArray *subDeletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteSubCommandPredicate];

                NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLAddCommand class]];
                NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                NSPredicate *addSubmenuPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass: %@", [SDLAddSubMenu class]];
                NSArray *submenu = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addSubmenuPredicate];

                expect(deletes).to(haveCount(0));
                expect(subDeletes).to(haveCount(1));
                expect(adds).to(haveCount(0));
                expect(submenu).to(haveCount(0));

                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(haveCount(3));
            });
        });

        context(@"when cells remain the same", ^{
            beforeEach(^{
                testCurrentMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textOnlyCell2, textAndImageCell] copyItems:YES];
                [SDLMenuReplaceUtilities updateIdsOnMenuCells:testCurrentMenu parentId:ParentIdNotFound];

                testNewMenu = [[NSArray alloc] initWithArray:@[textOnlyCell, textOnlyCell2, textAndImageCell] copyItems:YES];
            });

            it(@"should send dynamic deletes first then dynamic adds when cells stay the same", ^{
                testOp = [[SDLMenuReplaceOperation alloc] initWithConnectionManager:testConnectionManager fileManager:testFileManager windowCapability:testWindowCapability menuConfiguration:testMenuConfiguration currentMenu:testCurrentMenu updatedMenu:testNewMenu compatibilityModeEnabled:NO currentMenuUpdatedHandler:testCurrentMenuUpdatedBlock];
                [testOp start];

                NSPredicate *deleteCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLDeleteCommand class]];
                NSArray *deletes = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:deleteCommandPredicate];

                NSPredicate *addCommandPredicate = [NSPredicate predicateWithFormat:@"self isMemberOfClass:%@", [SDLAddCommand class]];
                NSArray *adds = [[testConnectionManager.receivedRequests copy] filteredArrayUsingPredicate:addCommandPredicate];

                expect(deletes).to(haveCount(0));
                expect(adds).to(haveCount(0));

                expect(testOp.isFinished).to(beTrue());
                expect(resultError).to(beNil());
                expect(resultMenuCells).to(haveCount(3));
            });
        });
    });
});

QuickSpecEnd
