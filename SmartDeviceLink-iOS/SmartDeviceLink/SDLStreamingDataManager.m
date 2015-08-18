//
//  SDLStreamingDataManager.m
//  SmartDeviceLink-iOS
//
//  Created by Joel Fischer on 8/11/15.
//  Copyright (c) 2015 smartdevicelink. All rights reserved.
//

#import "SDLStreamingDataManager.h"

#import "SDLAbstractProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SDLStreamingDataManager ()

@property (assign, nonatomic) BOOL videoSessionConnected;
@property (assign, nonatomic) BOOL audioSessionConnected;

@property (weak, nonatomic) SDLAbstractProtocol *protocol;

@property (copy, nonatomic, nullable) SDLStreamingStartBlock videoStartBlock;
@property (copy, nonatomic, nullable) SDLStreamingStartBlock audioStartBlock;

@end


@implementation SDLStreamingDataManager

- (instancetype)initWithProtocol:(SDLAbstractProtocol *)protocol {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _videoSessionConnected = NO;
    _audioSessionConnected = NO;
    _protocol = protocol;
    
    _videoStartBlock = nil;
    _audioStartBlock = nil;
    
    return self;
}

- (void)startVideoSessionWithStartBlock:(SDLStreamingStartBlock)startBlock {
    self.videoStartBlock = [startBlock copy];
    
    [self.protocol sendStartSessionWithType:SDLServiceType_Video];
}

- (void)startAudioStreamingWithStartBlock:(SDLStreamingStartBlock)startBlock {
    self.audioStartBlock = [startBlock copy];
    
    [self.protocol sendStartSessionWithType:SDLServiceType_Audio];
}

- (void)stopVideoSession {
    [self.protocol sendEndSessionWithType:SDLServiceType_Video];
}

- (void)stopAudioSession {
    [self.protocol sendEndSessionWithType:SDLServiceType_Audio];
}

- (BOOL)sendVideoData:(CMSampleBufferRef)bufferRef {
    if (!self.videoSessionConnected) {
        return NO;
    }
    
    // TODO (Joel F.)[2015-08-17]: Somehow monitor connection to make sure we're not clogging the connection with data.
    dispatch_async([self.class sdl_streamingDataSerialQueue], ^{
        NSData *elementaryStreamData = [self.class sdl_encodeElementaryStreamWithBufferRef:bufferRef];
        [self.protocol sendRawData:elementaryStreamData withServiceType:SDLServiceType_Video];
    });
    
    return YES;
}

- (BOOL)sendAudioData:(NSData *)pcmAudioData {
    if (!self.audioSessionConnected) {
        return NO;
    }
    
    dispatch_async([self.class sdl_streamingDataSerialQueue], ^{
        [self.protocol sendRawData:pcmAudioData withServiceType:SDLServiceType_Audio];
    });
    
    return YES;
}


#pragma mark - SDLProtocolListener Methods

- (void)handleProtocolStartSessionACK:(SDLServiceType)serviceType sessionID:(Byte)sessionID version:(Byte)version {
    switch (serviceType) {
        case SDLServiceType_Audio: {
            self.audioSessionConnected = YES;
            self.audioStartBlock(YES);
            self.audioStartBlock = nil;
        } break;
        case SDLServiceType_Video: {
            self.videoSessionConnected = YES;
            self.videoStartBlock(YES);
            self.videoStartBlock = nil;
        } break;
        default: break;
    }
}

- (void)handleProtocolStartSessionNACK:(SDLServiceType)serviceType {
    switch (serviceType) {
        case SDLServiceType_Audio: {
            self.audioStartBlock(NO);
            self.audioStartBlock = nil;
        } break;
        case SDLServiceType_Video: {
            self.videoStartBlock(NO);
            self.videoStartBlock = nil;
        } break;
        default: break;
    }
}

- (void)handleProtocolEndSessionACK:(SDLServiceType)serviceType {
    switch (serviceType) {
        case SDLServiceType_Audio: {
            self.audioSessionConnected = NO;
        } break;
        case SDLServiceType_Video: {
            self.videoSessionConnected = NO;
        } break;
        default: break;
    }
}

- (void)handleProtocolEndSessionNACK:(SDLServiceType)serviceType {
    // TODO (Joel F.)[2015-08-17]: This really, really shouldn't ever happen. Should we assert? Do nothing? We don't have any additional info on why this failed.
}


#pragma mark - Encoding

+ (NSData *)sdl_encodeElementaryStreamWithBufferRef:(CMSampleBufferRef)bufferRef {
    NSMutableData *elementaryStream = [NSMutableData data];
    BOOL isIFrame = NO;
    CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(bufferRef, 0);
    
    if (CFArrayGetCount(attachmentsArray)) {
        CFBooleanRef notSync;
        CFDictionaryRef dict = CFArrayGetValueAtIndex(attachmentsArray, 0);
        BOOL keyExists = CFDictionaryGetValueIfPresent(dict,
                                                       kCMSampleAttachmentKey_NotSync,
                                                       (const void **)&notSync);
        
        // Find out if the sample buffer contains an I-Frame (sync frame). If so we will write the SPS and PPS NAL units to the elementary stream.
        isIFrame = !keyExists || !CFBooleanGetValue(notSync);
    }
    
    // This is the start code that we will write to the elementary stream before every NAL unit
    static const size_t startCodeLength = 4;
    static const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
    
    // Write the SPS and PPS NAL units to the elementary stream before every I-Frame
    if (isIFrame) {
        CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(bufferRef);
        
        // Find out how many parameter sets there are
        size_t numberOfParameterSets;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                           0, NULL, NULL,
                                                           &numberOfParameterSets,
                                                           NULL);
        
        // Write each parameter set to the elementary stream
        for (int i = 0; i < numberOfParameterSets; i++) {
            const uint8_t *parameterSetPointer;
            size_t parameterSetLength;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description,
                                                               i,
                                                               &parameterSetPointer,
                                                               &parameterSetLength,
                                                               NULL, NULL);
            
            // Write the parameter set to the elementary stream
            [elementaryStream appendBytes:startCode length:startCodeLength];
            [elementaryStream appendBytes:parameterSetPointer length:parameterSetLength];
        }
    }
    
    // Get a pointer to the raw AVCC NAL unit data in the sample buffer
    size_t blockBufferLength = 0;
    uint8_t *bufferDataPointer = NULL;
    CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(bufferRef),
                                0,
                                NULL,
                                &blockBufferLength,
                                (char **)&bufferDataPointer);
    
    // Loop through all the NAL units in the block buffer and write them to the elementary stream with start codes instead of AVCC length headers
    size_t bufferOffset = 0;
    static const int AVCCHeaderLength = 4;
    while (bufferOffset < blockBufferLength - AVCCHeaderLength) {
        // Read the NAL unit length
        uint32_t NALUnitLength = 0;
        memcpy(&NALUnitLength, bufferDataPointer + bufferOffset, AVCCHeaderLength);
        
        // Convert the length value from Big-endian to Little-endian
        NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
        [elementaryStream appendBytes:startCode length:startCodeLength];
        
        // Write the NAL unit without the AVCC length header to the elementary stream
        [elementaryStream appendBytes:bufferDataPointer + bufferOffset + AVCCHeaderLength length:NALUnitLength];
        
        // Move to the next NAL unit in the block buffer
        bufferOffset += AVCCHeaderLength + NALUnitLength;
    }
    
    return elementaryStream;
}

+ (dispatch_queue_t)sdl_streamingDataSerialQueue {
    static dispatch_queue_t streamingDataQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        streamingDataQueue = dispatch_queue_create("com.sdl.videoaudiostreaming.encoder", DISPATCH_QUEUE_SERIAL);
    });
    
    return streamingDataQueue;
}

@end

NS_ASSUME_NONNULL_END
