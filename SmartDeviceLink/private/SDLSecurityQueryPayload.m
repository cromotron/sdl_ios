//
//  SDLSecurityQueryPayload.m
//  SmartDeviceLink
//
//  Created by Frank Elias on 7/28/21.
//  Copyright © 2021 smartdevicelink. All rights reserved.
//

#import "SDLSecurityQueryPayload.h"

#import "SDLLogMacros.h"

const NSUInteger SECURITY_QUERY_HEADER_SIZE = 12;

NS_ASSUME_NONNULL_BEGIN

@implementation SDLSecurityQueryPayload

- (nullable instancetype)initWithData:(NSData *)data {
    unsigned long dataLength = data.length;

    if (data == nil || dataLength == 0) {
        SDLLogW(@"RPC Payload data is nil");
        return nil;
    }

    if (dataLength < SECURITY_QUERY_HEADER_SIZE) {
        SDLLogW(@"RPC Payload error: not enough data to form RPC header");
        return nil;
    }

    if (self = [self init]) {
        @try {
            // Setup our pointers for data access
            UInt8 *bytePointer = (UInt8 *)data.bytes;
            UInt32 *ui32Pointer = (UInt32 *)data.bytes;

            // Extract the parts
            UInt8 rpcType = (bytePointer[0] & 0xFF) >> 8;

            self.rpcType = rpcType;

            UInt32 functionID = ui32Pointer[0];
            functionID = CFSwapInt32BigToHost(functionID) & 0x00FFFFF;
            self.functionID = functionID;

            UInt32 correlationID = ui32Pointer[1];
            correlationID = CFSwapInt32BigToHost(correlationID);
            self.correlationID = correlationID;

            UInt32 jsonDataSize = ui32Pointer[2];
            jsonDataSize = CFSwapInt32BigToHost(jsonDataSize);

            NSData *jsonData = nil;
            NSUInteger offsetOfJSONData = SECURITY_QUERY_HEADER_SIZE;
            if (jsonDataSize > 0 && jsonDataSize <= dataLength - SECURITY_QUERY_HEADER_SIZE) {
                jsonData = [data subdataWithRange:NSMakeRange(offsetOfJSONData, jsonDataSize)];
            }
            self.jsonData = jsonData;

            NSData *binaryData = nil;
            NSUInteger offsetOfBinaryData = SECURITY_QUERY_HEADER_SIZE + jsonDataSize;
            NSUInteger binaryDataSize = data.length - jsonDataSize - SECURITY_QUERY_HEADER_SIZE;
            if (binaryDataSize > 0) {
                binaryData = [data subdataWithRange:NSMakeRange(offsetOfBinaryData, binaryDataSize)];
            }
            self.binaryData = binaryData;

        } @catch (NSException *e) {
            SDLLogW(@"SDLSecurityQueryPayload error: %@", e);
            return nil;
        }
    }

    return self;
}

- (NSData *)data {
    // Header is:
    // RPC Type - first 8 bits
    // RPC Function ID - next 24 bits
    // Correlation ID - next 32 bits
    // JSON size - next 32 bits
    UInt8 headerBuffer[SECURITY_QUERY_HEADER_SIZE];
    *(UInt32 *)&headerBuffer[0] = CFSwapInt32HostToBig(self.functionID);
    *(UInt32 *)&headerBuffer[4] = CFSwapInt32HostToBig(self.correlationID);
    *(UInt32 *)&headerBuffer[8] = CFSwapInt32HostToBig((UInt32)self.jsonData.length);
    UInt8 rpcType = (Byte)((self.rpcType & 0xFF) << 8);
    headerBuffer[0] &= 0xFF;
    headerBuffer[0] |= rpcType;

    // Serialize the header, the json data then the binary data
    NSMutableData *dataOut = [NSMutableData dataWithCapacity:[self size]];
    [dataOut appendBytes:&headerBuffer length:12];
    [dataOut appendData:self.jsonData];
    [dataOut appendData:self.binaryData];

    return dataOut;
}

- (NSUInteger)size {
    NSUInteger headerSize = SECURITY_QUERY_HEADER_SIZE;
    NSUInteger jsonDataSize = self.jsonData.length;
    NSUInteger binaryDataSize = self.binaryData.length;

    return (headerSize + jsonDataSize + binaryDataSize);
}

- (NSString *)description {
    NSMutableString *description = [[NSMutableString alloc] init];
    [description appendFormat:@" rpcType:%i, functionID:%i, correlationID:%i, json:%lu bytes, binary:%lu bytes", self.rpcType, (unsigned int)self.functionID, (unsigned int)self.correlationID, (unsigned long)self.jsonData.length, (unsigned long)self.binaryData.length];

    return description;
}

+ (nullable id)rpcPayloadWithData:(NSData *)data {
    return [[SDLSecurityQueryPayload alloc] initWithData:data];
}
@end

NS_ASSUME_NONNULL_END
