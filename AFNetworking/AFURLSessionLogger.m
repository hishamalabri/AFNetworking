#import "AFURLSessionLogger.h"
#import <CocoaLumberjack/CocoaLumberjack.h>

@interface NSDictionary (AFCensorableDictionary)
- (NSDictionary *)af_censoredDictionaryWithKeys:(NSArray<NSString *> *)keys;
@end

@interface NSArray (AFCensorableArray)
- (NSArray *)af_censoredArrayWithKeys:(NSArray<NSString *> *)keys;
@end


@implementation NSDictionary (AFCensorableDictionary)

- (NSDictionary *)af_censoredDictionaryWithKeys:(NSArray<NSString *> *)keysToCensor {
    NSMutableDictionary *censoredDictionary = [NSMutableDictionary dictionaryWithDictionary:self];
    for (NSString *key in keysToCensor) {
        if ([censoredDictionary.allKeys containsObject:key]) {
            id currentValue = censoredDictionary[key];
            if (currentValue != [NSNull null]) {
                censoredDictionary[key] = key;
            } else {
                censoredDictionary[key] = @"empty";
            }
        }
    }
    for (NSString *key in censoredDictionary.allKeys) {
        id tmpElement = censoredDictionary[key];
        if ([tmpElement isKindOfClass:NSArray.class]) {
            tmpElement = [tmpElement af_censoredArrayWithKeys:keysToCensor];
        } else if ([tmpElement isKindOfClass:NSDictionary.class]) {
            tmpElement = [tmpElement af_censoredDictionaryWithKeys:keysToCensor];
        }
        censoredDictionary[key] = tmpElement;
    }
    
    return censoredDictionary.copy;
}

@end


@implementation NSArray (AFCensorableArray)

- (NSArray *)af_censoredArrayWithKeys:(NSArray<NSString *> *)keysToCensor {
    NSMutableArray *tmp_array = [NSMutableArray arrayWithArray:self];
    for (NSUInteger i = 0; i < tmp_array.count; i++) {
        id tempElement = tmp_array[i];
        if ([tempElement isKindOfClass:NSArray.class]) {
            tempElement = [tempElement af_censoredArrayWithKeys:keysToCensor];
        } else if ([tempElement isKindOfClass:NSDictionary.class]) {
            tempElement = [tempElement af_censoredDictionaryWithKeys:keysToCensor];
        }
        tmp_array[i] = tempElement;
    }
    return tmp_array.copy;
}

@end



#define AFLogInfo(fmt, ...) DDLogInfo((@"INFO  : " fmt), ##__VA_ARGS__)
#define AFLogError(fmt, ...) DDLogError((@"ERROR : " fmt), ##__VA_ARGS__)



static AFURLSessionLoggerOptions afRestClientLogging = AFURLSessionLoggerOptionsRequestResponse | AFURLSessionLoggerOptionsRequestResponseBody;
static const int ddLogLevel = DDLogLevelInfo;


@implementation AFURLSessionLogger

+ (NSMutableDictionary<NSString *, NSDate *> *)taskStartDateDictionary {
    static NSMutableDictionary *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NSMutableDictionary alloc] init];
    });
    return sharedInstance;
}

+ (NSMutableArray<NSString *> *)censoredHeaders {
    static NSMutableArray *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NSMutableArray alloc] init];
    });
    return sharedInstance;
}

+ (NSMutableArray<NSString *> *)censoredJsonBodyKeys {
    static NSMutableArray *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[NSMutableArray alloc] init];
    });
    return sharedInstance;
}

+ (void)logRequestStarted:(NSURLSessionTask *)task session:(NSURLSession *)session {
    if (!([AFURLSessionLogger restClientLogging] & AFURLSessionLoggerOptionsRequestResponse)) {
        return;
    }
    self.taskStartDateDictionary[[self getTaskIdKey:task session:session]] = [NSDate date];
    NSString *method = task.originalRequest.HTTPMethod;
    NSString *finalUrl = task.originalRequest.URL.absoluteString;
    NSString *allHeaders = [self getFullRequestHeaders:task session:session];
    NSString *bodyLogString = [self getRequestBodyLogString:task];
    AFLogInfo(@"Session %@ Task %@: %@ %@\nRequest Headers: %@%@", session.sessionDescription,
            @(task.taskIdentifier), method, finalUrl, allHeaders,
            bodyLogString);
}

+ (void)logRequestComplete:(NSURLSessionTask *)task session:(NSURLSession *)session responseBody:(NSData *)responseBody error:(NSError *)error {
    if (!([AFURLSessionLogger restClientLogging] & AFURLSessionLoggerOptionsRequestResponse)) {
        return;
    }
    NSString *responseDescription = [self buildResponseDescription:task session:session responseBody:responseBody];
    if (error) {
        AFLogError(@"Session %@ Task %@ Failed requesting: %@\nError: %@", session.sessionDescription, @(task.taskIdentifier),
                   responseDescription, error.localizedDescription);
    } else {
        AFLogInfo(@"Session %@ Task %@ Success requesting: %@", session.sessionDescription, @(task.taskIdentifier),
                  responseDescription);
    }
}

+ (NSString *)buildResponseDescription:(NSURLSessionTask *)task session:(NSURLSession *)session responseBody:(NSData *)responseBody {
    NSMutableArray<NSString *> *responseDescriptions = [NSMutableArray new];
    [responseDescriptions addObject:[NSString stringWithFormat:@"%@ %@", task.originalRequest.HTTPMethod, task.originalRequest.URL.absoluteString]];
    NSDate *startDate = self.taskStartDateDictionary[[self getTaskIdKey:task session:session]];
    if (startDate) {
        [self.taskStartDateDictionary removeObjectForKey:[self getTaskIdKey:task session:session]];
        [responseDescriptions addObject:[NSString stringWithFormat:@"Duration: %.02f seconds", [[NSDate date] timeIntervalSinceDate:startDate]]];
    }
    if ([task.response isKindOfClass:NSHTTPURLResponse.class]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) task.response;
        [responseDescriptions addObject:[NSString stringWithFormat:@"Response Status: %@", @(httpResponse.statusCode)]];
        [responseDescriptions addObject:[NSString stringWithFormat:@"Response Headers: %@", [self toJsonString:[self censorHTTPHeaders:[httpResponse allHeaderFields]]]]];
    }
    if (([AFURLSessionLogger restClientLogging] & AFURLSessionLoggerOptionsRequestResponseBody)) {
        NSString *responseBodyString = [self getDataBodyString:responseBody];
        if (responseBodyString.length > 0) {
            [responseDescriptions addObject:[NSString stringWithFormat:@"Response Body: %@", responseBodyString]];
        }
    }
    return [responseDescriptions componentsJoinedByString:@"\n"];
}

+ (NSString *)getDataBodyString:(NSData *)responseBody {
    if (responseBody && responseBody.length > 0) {
        NSMutableString *dataBodyString = [NSMutableString stringWithFormat:@"%@ bytes\n", @(responseBody.length)];
        NSString *responseAsString = [[NSString alloc] initWithData:responseBody encoding:NSUTF8StringEncoding];
        if (responseAsString.length > 0) {
            [dataBodyString appendString:[self censorBody:responseAsString]];
        } else {
            [dataBodyString appendString:@"<binary>"];
        }
        return dataBodyString;
    }
    return @"";
}

+ (NSString *)getRequestBodyLogString:(NSURLSessionTask *)task {
    if (!([AFURLSessionLogger restClientLogging] & AFURLSessionLoggerOptionsRequestResponseBody)) {
        return @"";
    }
    if (task.originalRequest.HTTPBody == nil || task.originalRequest.HTTPBody.length == 0) {
        return @"";
    }
    return [NSString stringWithFormat:@"\nRequest Body: %@", [self getDataBodyString:task.originalRequest.HTTPBody]];
}

+ (NSString *)getFullRequestHeaders:(NSURLSessionTask *)task session:(NSURLSession *)session {
    NSMutableDictionary *allHeaders = session.configuration.HTTPAdditionalHeaders ? [session.configuration.HTTPAdditionalHeaders mutableCopy] : [@{} mutableCopy];
    [allHeaders addEntriesFromDictionary:task.originalRequest.allHTTPHeaderFields];
    NSDictionary *censoredHeaders = [self censorHTTPHeaders:allHeaders];
    return [self toJsonString:censoredHeaders];
}

#pragma mark - Helper

+ (NSString *)getTaskIdKey:(NSURLSessionTask *)task session:(NSURLSession *)session {
    return [NSString stringWithFormat:@"%@-%@", session.sessionDescription, @(task.taskIdentifier)];
}

+ (NSString *)toJsonString:(id)jsonObject {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                       options:(NSJSONWritingOptions)0
                                                         error:&error];
    if (!jsonData || error) {
        if ([jsonObject isKindOfClass:[NSDictionary class]]) {
            return @"{}";
        } else {
            return @"[]";
        }
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (NSString *)removeMultipleSpaces:(NSString *)target {
    return [[self removeMultipleSpacesRegex] stringByReplacingMatchesInString:target options:0 range:NSMakeRange(0, target.length) withTemplate:@" "];
}

+ (NSString *)removePasswords:(NSString *)target {
    return [[self removePasswordRegex] stringByReplacingMatchesInString:target options:0 range:NSMakeRange(0, target.length) withTemplate:@"REDACTED"];
}

#pragma mark - Logging Settings

+ (AFURLSessionLoggerOptions)restClientLogging {
    return afRestClientLogging;
}

+ (void)setRestClientLogging:(AFURLSessionLoggerOptions)restClientLogging {
    afRestClientLogging = restClientLogging;
}
                    
#pragma mark - Censoring

+ (NSDictionary *)censorHTTPHeaders:(NSDictionary *)allHeaders {
    NSMutableArray<NSString *> *censoredHeaders = [[AFURLSessionLogger censoredHeaders] mutableCopy];
    NSMutableDictionary *mutableHeaders = [allHeaders mutableCopy];
    for (NSString *key in mutableHeaders.allKeys) {
        if ([censoredHeaders containsObject:key]) {
            [mutableHeaders setValue:key forKey:key];
        }
    }
    return [mutableHeaders copy];
}

+ (NSString *)censorBody:(NSString *)body {
    NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    id bodyJson = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&error];
    if (bodyJson && !error && ([bodyJson isKindOfClass:NSArray.class] || [bodyJson isKindOfClass:NSDictionary.class])) {
        if ([bodyJson isKindOfClass:NSArray.class]) {
            return [self toJsonString:[bodyJson af_censoredArrayWithKeys:self.censoredJsonBodyKeys]];
        } else if ([bodyJson isKindOfClass:NSDictionary.class]) {
            return [self toJsonString:[bodyJson af_censoredDictionaryWithKeys:self.censoredJsonBodyKeys]];
        }
        return body;
    } else {
        body = [self removeMultipleSpaces:[body stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
        return [self removePasswords:body];
    }
}

+ (NSRegularExpression *)removeMultipleSpacesRegex {
    static NSRegularExpression *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        sharedInstance = [NSRegularExpression regularExpressionWithPattern:@"  +" options:NSRegularExpressionCaseInsensitive error:&error];
        if (error) {
            AFLogError(@"Error creating remove multiple spaces regex. %@", error.localizedDescription);
        }
    });
    return sharedInstance;
}

+ (NSRegularExpression *)removePasswordRegex {
    static NSRegularExpression *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        sharedInstance = [NSRegularExpression regularExpressionWithPattern:@"  +" options:NSRegularExpressionCaseInsensitive error:&error];
        if (error) {
            AFLogError(@"Error creating remove multiple spaces regex. %@", error.localizedDescription);
        }
    });
    return sharedInstance;
}

@end
