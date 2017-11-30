//
//  SDLBinaryAudioManager.m
//  SmartDeviceLink-Example
//
//  Created by Joel Fischer on 10/24/17.
//  Copyright © 2017 smartdevicelink. All rights reserved.
//

#import "SDLAudioStreamManager.h"

#import "SDLAudioFile.h"
#import "SDLLogMacros.h"
#import "SDLManager.h"
#import "SDLPCMAudioConverter.h"
#import "SDLPCMAudioStreamManagerDelegate.h"
#import "SDLStreamingMediaLifecycleManager.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const SDLErrorDomainPCMAudioStreamManager = @"com.sdl.extension.pcmAudioStreamManager";

typedef NS_ENUM(NSInteger, SDLPCMAudioStreamManagerError) {
    SDLPCMAudioStreamManagerErrorNotConnected = -1,
    SDLPCMAudioStreamManagerErrorNoQueuedAudio = -2
};

@interface SDLAudioStreamManager ()

@property (weak, nonatomic) SDLStreamingMediaLifecycleManager *streamManager;
@property (strong, nonatomic) NSMutableArray<SDLAudioFile *> *mutableQueue;
@property (strong, nonatomic) dispatch_queue_t transcodeQueue;

@property (assign, nonatomic) BOOL shouldPlayWhenReady;

@end

@implementation SDLAudioStreamManager

- (instancetype)initWithManager:(SDLStreamingMediaLifecycleManager *)streamManager {
    self = [super init];
    if (!self) { return nil; }

    _mutableQueue = [NSMutableArray array];
    _transcodeQueue = dispatch_queue_create("com.sdl.pcmAudioTranscode", DISPATCH_QUEUE_SERIAL);
    _shouldPlayWhenReady = NO;

    _streamManager = streamManager;

    return self;
}

- (void)setSdlManager:(nullable SDLManager *)sdlManager {
    _streamManager = sdlManager.streamManager;
}

- (NSArray<SDLFile *> *)queue {
    return [_mutableQueue copy];
}

- (void)pushWithContentsOfURL:(NSURL *)fileURL {
    __weak SDLAudioStreamManager *weakSelf = self;
    dispatch_async(_transcodeQueue, ^{
        [weakSelf sdl_pushWithContentsOfURL:fileURL];
    });
}

- (void)sdl_pushWithContentsOfURL:(NSURL *)fileURL {
    // Convert and store in the queue
    NSError *error = nil;
    SDLPCMAudioConverter *converter = [[SDLPCMAudioConverter alloc] initWithFileURL:fileURL];
    NSURL *_Nullable outputFile = [converter convertFileWithError:&error];
    UInt32 estimatedDuration = converter.estimatedDuration;

    if (outputFile == nil) {
        SDLLogW(@"Error converting file to CAF / PCM: %@", error);
        [self.delegate audioStreamManager:self errorDidOccurForFile:[[SDLAudioFile alloc] initWithFileURL:fileURL estimatedDuration:UINT32_MAX] error:error];
        return;
    }

    SDLAudioFile *audioFile = [[SDLAudioFile alloc] initWithFileURL:outputFile estimatedDuration:estimatedDuration];
    [self.mutableQueue addObject:audioFile];

    if (self.shouldPlayWhenReady) {
        [self playNextWhenReady];
    }
}

- (BOOL)playNextWhenReady {
    if ((self.mutableQueue.count == 0)) {
        self.shouldPlayWhenReady = YES;
        return NO;
    }

    if (!self.streamManager.isAudioConnected) {
        NSError *error = [NSError errorWithDomain:SDLErrorDomainPCMAudioStreamManager code:SDLPCMAudioStreamManagerErrorNotConnected userInfo:nil];
        [self.delegate audioStreamManager:self errorDidOccurForFile:self.mutableQueue.firstObject error:error];
    }

    self.shouldPlayWhenReady = NO;
    __block SDLAudioFile *file = self.mutableQueue.firstObject;
    [self.mutableQueue removeObjectAtIndex:0];

    // Strip the first 52 byte (because of WAVE format) and send to the audio stream
    SDLLogD(@"Playing audio file: %@", file.fileURL);
    NSData *audioData = [file.data subdataWithRange:NSMakeRange(5760, (file.data.length - 5760))]; // TODO: We have to find out how to properly strip a header, but /shrug
    BOOL success = [self.streamManager sendAudioData:audioData];

    __weak SDLAudioStreamManager *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((audioData.length / 32000) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSError *error = nil;
        [weakSelf.delegate audioStreamManager:self fileDidFinishPlaying:file successfully:success];
        SDLLogD(@"Ending Audio file: %@", file.fileURL);
        [[NSFileManager defaultManager] removeItemAtURL:file.fileURL error:&error];
        if (error != nil) {
            [weakSelf.delegate audioStreamManager:self errorDidOccurForFile:file error:error];
        }
    });

    return YES;
}

- (void)stop {
    self.shouldPlayWhenReady = NO;
    [self.mutableQueue removeAllObjects];
}

@end

NS_ASSUME_NONNULL_END
