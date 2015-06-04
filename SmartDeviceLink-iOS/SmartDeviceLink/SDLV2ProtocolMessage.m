//  SDLSmartDeviceLinkV2ProtocolMessage.m
//

#import "SDLFunctionID.h"
#import "SDLJsonDecoder.h"
#import "SDLNames.h"
#import "SDLProtocolHeader.h"
#import "SDLRPCPayload.h"
#import "SDLV2ProtocolMessage.h"


@implementation SDLV2ProtocolMessage

- (instancetype)initWithHeader:(SDLProtocolHeader*)header andPayload:(NSData *)payload {
	if (self = [self init]) {
        self.header = header;
        self.payload = payload;
    }
    return self;
}

// Convert RPC payload to dictionary (for consumption by RPC layer)
- (NSDictionary *)rpcDictionary {
    // Only applicable to RPCs
    if (self.header.serviceType != SDLServiceType_RPC) {
        return nil;
    }

    NSMutableDictionary* rpcMessageAsDictionary = [[NSMutableDictionary alloc] init];

    // Parse the payload as RPC struct
    SDLRPCPayload *rpcPayload = [SDLRPCPayload rpcPayloadWithData:self.payload];

    // Create the inner dictionary with the RPC properties
    NSMutableDictionary *innerDictionary = [[NSMutableDictionary alloc] init];
    NSString *functionName = [[[SDLFunctionID alloc] init] getFunctionName:rpcPayload.functionID];
    [innerDictionary setObject:functionName forKey:NAMES_operation_name];
    [innerDictionary setObject:[NSNumber numberWithInt:rpcPayload.correlationID] forKey:NAMES_correlationID];

    // Get the json data from the struct
    if(rpcPayload.jsonData) {
        NSDictionary *jsonDictionary = [[SDLJsonDecoder instance] decode:rpcPayload.jsonData];
        if(jsonDictionary) {
            [innerDictionary setObject:jsonDictionary forKey:NAMES_parameters];
        }
    } // TODO: (Joel F.)[2015-05-20] Handle the error case

    // Store it in the containing dictionary
    UInt8 rpcType = rpcPayload.rpcType;
    NSArray *rpcTypeNames = @[NAMES_request, NAMES_response, NAMES_notification];
    [rpcMessageAsDictionary setObject:innerDictionary forKey:rpcTypeNames[rpcType]];

    // The bulk data also goes in the dictionary
    if (rpcPayload.binaryData) {
        [rpcMessageAsDictionary setObject:rpcPayload.binaryData forKey:NAMES_bulkData];
    }

    return rpcMessageAsDictionary;
    
}
@end