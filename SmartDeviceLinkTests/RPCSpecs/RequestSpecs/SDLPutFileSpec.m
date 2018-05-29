//
//  SDLPutFileSpec.m
//  SmartDeviceLink


#import <Foundation/Foundation.h>

#import <Quick/Quick.h>
#import <Nimble/Nimble.h>

#import "SDLFileType.h"
#import "SDLNames.h"
#import "SDLPutFile.h"

#import <zlib.h>


@interface SDLPutFile()
+ (unsigned long)sdl_getCRC32ChecksumForBulkData:(NSData *)data;
@end

QuickSpecBegin(SDLPutFileSpec)

describe(@"Getter/Setter Tests", ^ {
    it(@"Should set and get correctly", ^ {
        SDLPutFile* testRequest = [[SDLPutFile alloc] init];
        
        testRequest.syncFileName = @"fileName";
        testRequest.fileType = SDLFileTypeJPEG;
        testRequest.persistentFile = @YES;
        testRequest.systemFile = @NO;
        testRequest.offset = @987654321;
        testRequest.length = @123456789;
        testRequest.crc = @0xffffffff;
        
        expect(testRequest.syncFileName).to(equal(@"fileName"));
        expect(testRequest.fileType).to(equal(SDLFileTypeJPEG));
        expect(testRequest.persistentFile).to(equal(@YES));
        expect(testRequest.systemFile).to(equal(@NO));
        expect(testRequest.offset).to(equal(@987654321));
        expect(testRequest.length).to(equal(@123456789));
        expect(testRequest.crc).to(equal(0xffffffff));
    });
    
    it(@"Should set correctly when initialized with a dictionary", ^ {
        NSMutableDictionary* dict = [@{SDLNameRequest:
                                           @{SDLNameParameters:
                                                @{ SDLNameSyncFileName:@"fileName",
                                                    SDLNameFileType:SDLFileTypeJPEG,
                                                    SDLNamePersistentFile:@YES,
                                                    SDLNameSystemFile:@NO,
                                                    SDLNameOffset:@987654321,
                                                    SDLNameLength:@123456789,
                                                   SDLNameCRC:@0xffffffff},
                                                    SDLNameOperationName:SDLNamePutFile}} mutableCopy];
        SDLPutFile* testRequest = [[SDLPutFile alloc] initWithDictionary:dict];
        
        expect(testRequest.syncFileName).to(equal(@"fileName"));
        expect(testRequest.fileType).to(equal(SDLFileTypeJPEG));
        expect(testRequest.persistentFile).to(equal(@YES));
        expect(testRequest.systemFile).to(equal(@NO));
        expect(testRequest.offset).to(equal(@987654321));
        expect(testRequest.length).to(equal(@123456789));
        expect(testRequest.crc).to(equal(@0xffffffff));
    });

    it(@"Should set correctly when initialized with convenience init", ^ {
        SDLPutFile* testRequest = [[SDLPutFile alloc] initWithFileName:@"fileName" fileType:SDLFileTypeWAV crc:0xffffffff];

        expect(testRequest.syncFileName).to(equal(@"fileName"));
        expect(testRequest.fileType).to(equal(SDLFileTypeWAV));
        expect(testRequest.crc).to(equal(0xffffffff));
    });

    it(@"Should set correctly when initialized with convenience init with persistance", ^ {
        SDLPutFile* testRequest = [[SDLPutFile alloc] initWithFileName:@"fileName" fileType:SDLFileTypePNG persistentFile:false crc:0xffffffff];

        expect(testRequest.syncFileName).to(equal(@"fileName"));
        expect(testRequest.fileType).to(equal(SDLFileTypePNG));
        expect(testRequest.persistentFile).to(beFalse());
        expect(testRequest.crc).to(equal(0xffffffff));
    });

    it(@"Should set correctly when initialized with convenience init with file data information", ^ {
        SDLPutFile* testRequest = [[SDLPutFile alloc] initWithFileName:@"fileName" fileType:SDLFileTypeMP3 persistentFile:true systemFile:true offset:45 length:34 crc:0xffffffff];

        expect(testRequest.syncFileName).to(equal(@"fileName"));
        expect(testRequest.fileType).to(equal(SDLFileTypeMP3));
        expect(testRequest.persistentFile).to(beTrue());
        expect(testRequest.systemFile).to(beTrue());
        expect(testRequest.offset).to(equal(45));
        expect(testRequest.length).to(equal(34));
        expect(testRequest.crc).to(equal(0xffffffff));
    });

     it(@"Should set correctly when initialized with convenience init with bulk data", ^ {
         NSData *testFileData = [@"someTextData" dataUsingEncoding:NSUTF8StringEncoding];
         unsigned long testFileCRC32Checksum = [SDLPutFile sdl_getCRC32ChecksumForBulkData:testFileData];

         SDLPutFile* testRequest = [[SDLPutFile alloc] initWithFileName:@"fileName" fileType:SDLFileTypeMP3 persistentFile:true systemFile:true offset:45 length:34 bulkData:testFileData];

         expect(testRequest.syncFileName).to(equal(@"fileName"));
         expect(testRequest.fileType).to(equal(SDLFileTypeMP3));
         expect(testRequest.persistentFile).to(beTrue());
         expect(testRequest.systemFile).to(beTrue());
         expect(testRequest.offset).to(equal(45));
         expect(testRequest.length).to(equal(34));
         expect(testRequest.bulkData).to(equal(testFileData));
         expect(testRequest.crc).to(equal(testFileCRC32Checksum));
     });

    it(@"Should return nil if not set", ^ {
        SDLPutFile* testRequest = [[SDLPutFile alloc] init];
        
        expect(testRequest.syncFileName).to(beNil());
        expect(testRequest.fileType).to(beNil());
        expect(testRequest.persistentFile).to(beNil());
        expect(testRequest.systemFile).to(beNil());
        expect(testRequest.offset).to(beNil());
        expect(testRequest.length).to(beNil());
        expect(testRequest.crc).to(beNil());
    });

    describe(@"When creating a CRC32 checksum for the bulk data", ^{
        it(@"should create a checksum for data", ^{
            NSData *testFileData = [@"Somerandomtextdata" dataUsingEncoding:NSUTF8StringEncoding];
            unsigned long testFileCRC32Checksum = [SDLPutFile sdl_getCRC32ChecksumForBulkData:testFileData];

            expect(testFileCRC32Checksum).to(equal(testFileCRC32Checksum));
        });

        it(@"should not create a checksum if the data is nil", ^{
            NSData *testFileData = nil;
            unsigned long testFileCRC32Checksum = [SDLPutFile sdl_getCRC32ChecksumForBulkData:testFileData];

            expect(testFileCRC32Checksum).to(equal(0));
        });

        it(@"should not create a checksum if the data is empty", ^{
            NSData *testFileData = [NSData data];
            unsigned long testFileCRC32Checksum = [SDLPutFile sdl_getCRC32ChecksumForBulkData:testFileData];

            expect(testFileCRC32Checksum).to(equal(0));
        });
    });
});

QuickSpecEnd
