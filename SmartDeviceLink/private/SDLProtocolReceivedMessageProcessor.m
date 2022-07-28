//
//  SDLProtocolProcessMessageByte.m
//  SmartDeviceLink
//
//  Created by George Miller on 7/13/22.
//  Copyright © 2022 smartdevicelink. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SDLProtocolHeader.h"
#import "SDLProtocolReceivedMessageProcessor.h"
#import "SDLProtocolReceivedMessageRouter.h"
#import "SDLSecurityType.h"

typedef NS_ENUM(NSUInteger, StateEnum) {
    START_STATE = 0x0,
    SERVICE_TYPE_STATE = 0x02,
    CONTROL_FRAME_INFO_STATE = 0x03,
    SESSION_ID_STATE = 0x04,
    DATA_SIZE_1_STATE = 0x05,
    DATA_SIZE_2_STATE = 0x06,
    DATA_SIZE_3_STATE = 0x07,
    DATA_SIZE_4_STATE = 0x08,
    MESSAGE_1_STATE = 0x09,
    MESSAGE_2_STATE = 0x0A,
    MESSAGE_3_STATE = 0x0B,
    MESSAGE_4_STATE = 0x0C,
    DATA_PUMP_STATE = 0x0D,
    ERROR_STATE = -1,
};

@interface SDLProtocolReceivedMessageProcessor(){
    // State management
    StateEnum state;
    StateEnum prevState;
    
    // Message management
    BOOL endOfMessage;
    SDLProtocolHeader *header;
    
    // Used for error checking.  Practically part of state.
    UInt8 version;
    BOOL encrypted;
    int frameType;
    int dataLength;
    int dataBytesRemaining;
}

@end

@implementation SDLProtocolReceivedMessageProcessor

-(id)init {
    self = [super init];
    if (!self) { return nil; }

    version = 0;
    encrypted = false;
    frameType = 0x00;
    dataLength = 0;
    dataBytesRemaining = 0; //Counter for the data pump

    // Message management
    endOfMessage = 0;

    //Reset state
    [self ResetState];
    return self;
}

- (void)ResetState{
    // Flush Buffers
    self.headerBuffer = [NSMutableData dataWithCapacity:0];
    self.payloadBuffer = [NSMutableData dataWithCapacity:0];
    dataBytesRemaining = 0;
    
    // Reset state
    state = START_STATE;
    prevState = ERROR_STATE;
}

// Loop through the given bytes and call the state machine to process each byte.
- (void)processReceiveBuffer:(NSData *)receiveBuffer withMessageReadyBlock:(StateMachineMessageReadyBlock)messageReadyBlock{
    //get a pointer to the bytes because NSMutableData is layered
    const char *bytes = [receiveBuffer bytes];
    
    for (int i = 0; i < [receiveBuffer length]; i++) {
        endOfMessage = [self sdl_processMessagesStateMachine:(Byte)bytes[i]];

        // If we have reached the end of a message, we need to immediately call the message ready block with the completed data, then reset the buffers and keep pumping data into the state machine
        if (endOfMessage){
            endOfMessage = 0;
            messageReadyBlock(header.encrypted, header, [NSData dataWithData:self.payloadBuffer]);
            [self ResetState];
            return;
        }
    }
    
}

// This is the state machine
// It processes a single byte of a message, checks for errors,
// and builds up a header buffer and a payload buffer
// When the header and payload are complete, the message is processed
// The state of the state machine effectively tracks which byte of a message we are expecting next
// For reference: https://smartdevicelink.com/en/guides/sdl-overview-guides/protocol-spec/
// If a byte comes in that does not conform to spec, the buffers are flushed and state is reset.
- (BOOL)sdl_processMessagesStateMachine:(Byte)currentByte {
    Byte serviceType = 0x00;
    Byte controlFrameInfo = 0; // "Frame Info" in the documentation
    BOOL endOfMessageFlag = NO;
    
    switch (state){
        case START_STATE:
            //Flush the buffers
            [self ResetState];
            
            // 4 bits for version
            // 4 highest bits (b1111 0000)
            version = (currentByte & 0xF0 ) >> 4;

            // 1 bit for either encryption or compression, depending on version. 4th lowest bit (b0000 1000)
            encrypted = (currentByte & 0x08 ) >> 3;
            
            // 3 bits for frameType. 3 lowest bits (b0000 0111)
            frameType = (currentByte & 0x07) >> 0;

            state = SERVICE_TYPE_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            
            // Check version for errors
            if ((version < 1 || version > 5)) {
                prevState = state;
                state = ERROR_STATE;
            }
            
            // Check for valid frameType
            if ((frameType < SDLFrameTypeControl) || (frameType > SDLFrameTypeConsecutive)) {
                prevState = state;
                state = ERROR_STATE;
                break;
            }
            break;
            
        case SERVICE_TYPE_STATE:
            // 8 bits for service type
            serviceType = currentByte;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            
            // Check for errors
            switch (serviceType) {
                case 0x00: //SessionType.CONTROL:
                case 0x07: //SessionType.RPC:
                case 0x0A: //SessionType.PCM (Audio):
                case 0x0B: //SessionType.NAV (Video):
                case 0x0F: //SessionType.BULK (Hybrid):
                    state = CONTROL_FRAME_INFO_STATE;
                    break;
                default:
                    prevState=state;
                    state = ERROR_STATE;
                    break;
            }
            break;
            
        case CONTROL_FRAME_INFO_STATE:
            // 8 bits for frame information
            controlFrameInfo = currentByte;
            state = SESSION_ID_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            
            // Check for errors. For these two frame types, the frame info should be 0x00
            if (((frameType == SDLFrameTypeFirst) || (frameType == SDLFrameTypeSingle)) && (controlFrameInfo != 0x00)){
                prevState=state;
                state = ERROR_STATE;
            }
            break;
            
        case SESSION_ID_STATE:
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            state = DATA_SIZE_1_STATE;
            break;
        
        // 32 bits for data size
        case DATA_SIZE_1_STATE:
            dataLength = 0;
            dataLength += (currentByte & 0xFF) << 24;
            state = DATA_SIZE_2_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            break;
            
        case DATA_SIZE_2_STATE:
            dataLength += (currentByte & 0xFF) << 16;
            state = DATA_SIZE_3_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            break;
            
        case DATA_SIZE_3_STATE:
            dataLength += (currentByte & 0xFF) << 8;
            state = DATA_SIZE_4_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            break;
            
        case DATA_SIZE_4_STATE:
            dataLength += (currentByte & 0xFF) << 0;
            state = MESSAGE_1_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            
            // Set the counter for the data pump.
            dataBytesRemaining = dataLength;
            
            // Version 1 does not have a message ID so we skip to the data pump, or the end.
            if( version == 1) {
                if (dataLength == 0) {
                    [self ResetState];
                } else {
                    state = DATA_PUMP_STATE;
                }
            }
            
            Byte headerSize = 0;
            if (version == 1) {
                headerSize = 8;
            } else {
                headerSize = 12;
            }
            
            int maxMtuSize = 0;
            if (version <= 2) {
                maxMtuSize = 1500;
            } else {
                maxMtuSize = 131084;
            }
            
            // Check data length (does it conform to spec?)
            if (dataLength >= (maxMtuSize - headerSize)) {
                prevState = state;
                state = ERROR_STATE;
                break;
            }
            
            // If this is the first frame, it is not encrypted, and the length is not 8 then error.
            if ((frameType == SDLFrameTypeFirst) && (dataLength != 0x08) && (encrypted == false)) {
                prevState = state;
                state = ERROR_STATE;
                break;
            }
            
            break;
            
        // 32 bits for data size (version 2+)
        case MESSAGE_1_STATE:
            state = MESSAGE_2_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            break;
            
        case MESSAGE_2_STATE:
            state = MESSAGE_3_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            break;
            
        case MESSAGE_3_STATE:
            state = MESSAGE_4_STATE;
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            break;
            
        case MESSAGE_4_STATE:
            if (dataLength == 0) {
                [self ResetState];
            } else {
                state = DATA_PUMP_STATE;
            }
            [self.headerBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            
            break;
        
        case DATA_PUMP_STATE:
            // The pump state takes bytes in and adds them to the payload array
            
            // Note that we do not set state here.
            // If we are pumping, state won't change.
            // If we are done pumping, the stateManager will reset the state.
            
            [self.payloadBuffer appendBytes:&currentByte length:sizeof(currentByte)];
            dataBytesRemaining--;
            
            // Check if all the bytes have been read
            if (dataBytesRemaining <= 0) {
                // Create a header
                header = [SDLProtocolHeader headerForVersion:version];
                [header parse:self.headerBuffer];
                
                // Flag that we have reached the end of a message
                endOfMessageFlag = 1;
            }
            break;

        case ERROR_STATE:
        default:
            [self ResetState];
            break;
    }
    
    return endOfMessageFlag;
}

@end
