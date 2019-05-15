#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Enum Options for Logging Level
 */
typedef NS_OPTIONS(NSUInteger, AFURLSessionLoggerOptions) {
    AFURLSessionLoggerOptionsNone = 0,
    AFURLSessionLoggerOptionsRequestResponse = 1 << 0,
    AFURLSessionLoggerOptionsRequestResponseBody = 1 << 1
};

@interface AFURLSessionLogger : NSObject

/**
 * Reduce/increase logging.
 * restClientLogging value for logging level.
 */
@property (class, nonatomic) AFURLSessionLoggerOptions restClientLogging;


/**
 * Add keys to censor from the headers.
 */
@property(nonatomic, class, readonly) NSMutableArray<NSString *> *censoredHeaders;

/**
 * Add keys to censor from the body logs.
 */
@property(nonatomic, class, readonly) NSMutableArray<NSString *> *censoredJsonBodyKeys;

+ (void)logRequestStarted:(NSURLSessionTask *)task session:(NSURLSession *)session;

+ (void)logRequestComplete:(NSURLSessionTask *)task session:(NSURLSession *)session responseBody:(NSData *)responseBody error:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
