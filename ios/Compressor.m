#import "Compressor.h"
#import <React/RCTBridgeModule.h>
//Image
#import "Image/ImageCompressor.h"
#import "Image/ImageCompressorOptions.h"
#import <React/RCTEventEmitter.h>
#import <AVFoundation/AVFoundation.h>

#define AlAsset_Library_Scheme @"assets-library"
@implementation Compressor
AVAssetWriter *assetWriter=nil;
static NSArray *metadatas;

- (NSArray *)metadatas
{
  if (!metadatas) {
    metadatas = @[
      @"albumName",
      @"artist",
      @"comment",
      @"copyrights",
      @"creationDate",
      @"date",
      @"encodedby",
      @"genre",
      @"language",
      @"location",
      @"lastModifiedDate",
      @"performer",
      @"publisher",
      @"title"
    ];
  }
  return metadatas;
}

RCT_EXPORT_MODULE()

//Image
RCT_EXPORT_METHOD(
    image_compress: (NSString*) imagePath
    optionsDict: (NSDictionary*) optionsDict
    resolver: (RCTPromiseResolveBlock) resolve
    rejecter: (RCTPromiseRejectBlock) reject) {
    @try {
        ImageCompressorOptions *options = [ImageCompressorOptions fromDictionary:optionsDict];
        [ImageCompressor getAbsoluteImagePath:imagePath completionHandler:^(NSString* absoluteImagePath){
            if(options.autoCompress)
            {
                NSString *result = [ImageCompressor autoCompressHandler:absoluteImagePath options:options];
                resolve(result);
            }
            else
            {
                NSString *result = [ImageCompressor manualCompressHandler:absoluteImagePath options:options];
                resolve(result);
            }
        }];
        
    }
    @catch (NSException *exception) {
        reject(exception.name, exception.reason, nil);
    }
}

//Audio
RCT_EXPORT_METHOD(
    compress_audio: (NSString*) filePath
    optionsDict: (NSDictionary*) optionsDict
    resolver: (RCTPromiseResolveBlock) resolve
    rejecter: (RCTPromiseRejectBlock) reject) {
    @try {
        if([filePath containsString:@"file://"])
        {
            filePath=[filePath stringByReplacingOccurrencesOfString:@"file://"
                                                    withString:@""];
        }
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDir;
        if (![fileManager fileExistsAtPath:filePath isDirectory:&isDir] || isDir){
            NSError *err = [NSError errorWithDomain:@"file not found" code:-15 userInfo:nil];
            reject([NSString stringWithFormat: @"%lu", (long)err.code], err.localizedDescription, err);
            return;
        }

          NSDictionary *assetOptions = @{AVURLAssetPreferPreciseDurationAndTimingKey: @YES};
          AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:filePath] options:assetOptions];
        NSString *quality=[optionsDict objectForKey:@"quality"];
        NSString *qualityConstant=[self getAudioQualityConstant:quality];
        [self audo_compress_helper:asset qualityConstant:qualityConstant complete:^(NSString *mp3Path, BOOL finished) {
            if(finished)
            {
                resolve([NSString stringWithFormat: @"file:/%@", mp3Path]);
            }
            else
            {
                reject(@"Error", @"Something went wrong", nil);
            }
            
        }];
       
    }
    @catch (NSException *exception) {
        reject(exception.name, exception.reason, nil);
    }
}
- (NSString *)getAudioQualityConstant:(NSString *)quality
{
    NSMutableArray *audioQualityArray = [[NSMutableArray alloc]initWithObjects:@"low", @"medium", @"high", nil];
    int index = [audioQualityArray indexOfObject:quality];
    switch (index) {
        case 0:
            return AVAssetExportPresetLowQuality;
            break;
        case 1:
            return AVAssetExportPresetMediumQuality;
            break;
        case 2:
            return AVAssetExportPresetHighestQuality;
            break;
    }
    return AVAssetExportPresetMediumQuality;
}

- (void)audo_compress_helper:(AVURLAsset *)avAsset qualityConstant:(NSString *)qualityConstant complete:(void (^)(NSString *mp3Path, BOOL finished))completeCallback {
    NSString *path;
    if ([avAsset.URL.scheme isEqualToString:AlAsset_Library_Scheme]) {
        path = avAsset.URL.query;
        if (path.length == 0) {
            completeCallback(nil, NO);
            return;
        }
        
    }else {
        path = avAsset.URL.path;
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            completeCallback(nil, NO);
            return;
        }
    }
    
    NSString *mp3Path = [ImageCompressor generateCacheFilePath:@"m4a"];;

    if ([[NSFileManager defaultManager] fileExistsAtPath:mp3Path]) {
        if (completeCallback)
            completeCallback(mp3Path, YES);
        return;
    }

    NSURL *mp3Url;
    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
    
    if ([compatiblePresets containsObject:qualityConstant]) {
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]
                                               initWithAsset:avAsset
                                               presetName:AVAssetExportPresetAppleM4A];

        mp3Url = [NSURL fileURLWithPath:mp3Path];
        exportSession.outputURL = mp3Url;
        exportSession.shouldOptimizeForNetworkUse = YES;
        exportSession.outputFileType = AVFileTypeAppleM4A;
        
 
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            BOOL finished = NO;
            switch ([exportSession status]) {
                case AVAssetExportSessionStatusFailed:
                    NSLog(@"AVAssetExportSessionStatusFailed, error:%@.", exportSession.error);
                    break;

                case AVAssetExportSessionStatusCancelled:
                    NSLog(@"AVAssetExportSessionStatusCancelled.");
                    break;

                case AVAssetExportSessionStatusCompleted:
                    NSLog(@"AVAssetExportSessionStatusCompleted.");
                    finished = YES;
                    break;

                case AVAssetExportSessionStatusUnknown:
                    NSLog(@"AVAssetExportSessionStatusUnknown");
                    break;

                case AVAssetExportSessionStatusWaiting:
                    NSLog(@"AVAssetExportSessionStatusWaiting");
                    break;

                case AVAssetExportSessionStatusExporting:
                    NSLog(@"AVAssetExportSessionStatusExporting");
                    break;

            }

            if (completeCallback)
                completeCallback(mp3Path, finished);
        }];
        
    }
}



//general
RCT_EXPORT_METHOD(
    generateFilePath: (NSString*) extension
    resolver: (RCTPromiseResolveBlock) resolve
    rejecter: (RCTPromiseRejectBlock) reject) {
    @try {
        NSString *outputUri =[ImageCompressor generateCacheFilePath:extension];
        resolve(outputUri);
    }
    @catch (NSException *exception) {
        reject(exception.name, exception.reason, nil);
    }
}

RCT_EXPORT_METHOD(
    getRealPath: (NSString*) path
    type: (NSString*) type
    resolver: (RCTPromiseResolveBlock) resolve
    rejecter: (RCTPromiseRejectBlock) reject) {
    @try {
        if([type isEqualToString:@"video"])
        {
            [ImageCompressor getAbsoluteVideoPath:path completionHandler:^(NSString* absoluteImagePath){
                resolve(absoluteImagePath);
            }];
        }
        else
        {
            [ImageCompressor getAbsoluteImagePath:path completionHandler:^(NSString* absoluteImagePath){
                resolve(absoluteImagePath);
            }];
        }
    }
    @catch (NSException *exception) {
        reject(exception.name, exception.reason, nil);
    }
}

//general
    RCT_EXPORT_METHOD(
        getFileSize: (NSString*) filePath
        resolver: (RCTPromiseResolveBlock) resolve
        rejecter: (RCTPromiseRejectBlock) reject) {
        @try {
            if([filePath containsString:@"file://"])
            {
                filePath=[filePath stringByReplacingOccurrencesOfString:@"file://"
                                                        withString:@""];
            }
            NSFileManager *fileManager = [NSFileManager defaultManager];
            BOOL isDir;
            if (![fileManager fileExistsAtPath:filePath isDirectory:&isDir] || isDir){
                NSError *err = [NSError errorWithDomain:@"file not found" code:-15 userInfo:nil];
                reject([NSString stringWithFormat: @"%lu", (long)err.code], err.localizedDescription, err);
                return;
            }
            NSDictionary *attrs = [fileManager attributesOfItemAtPath: filePath error: NULL];
            UInt32 fileSize = [attrs fileSize];
            NSString *fileSizeString = [@(fileSize) stringValue];
            resolve(fileSizeString);
        }
        @catch (NSException *exception) {
            reject(exception.name, exception.reason, nil);
        }
    }

- (NSString *)saveImage:(UIImage *)image withName:(NSString *)name {
    NSData *data = UIImageJPEGRepresentation(image, 1.0);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *directories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = directories[0];
    NSString *fullPath = [documentsDirectory stringByAppendingPathComponent:name];
    [fileManager createFileAtPath:fullPath contents:data attributes:nil];
    return fullPath;
}

RCT_EXPORT_METHOD(
    getVideoThumnail: (NSString*) filePath
    resolver: (RCTPromiseResolveBlock) resolve
    rejecter: (RCTPromiseRejectBlock) reject) {
  @try {
    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL URLWithString:filePath]];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = true;
    
    CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMake(1, 1) actualTime:nil error:nil];
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    NSDate *date = [NSDate date];
    NSString* uri = [self saveImage:image withName:[NSString stringWithFormat:@"%ld.webp", (long)@([date timeIntervalSince1970]).integerValue]];
    
    [ImageCompressor getAbsoluteImagePath:uri completionHandler:^(NSString *absoluteImagePath) {
      resolve(absoluteImagePath);
    }];
  }
  @catch (NSException *exception) {
      reject(exception.name, exception.reason, nil);
  }
}

#define FourCC2Str(code) (char[5]){(code >> 24) & 0xFF, (code >> 16) & 0xFF, (code >> 8) & 0xFF, code & 0xFF, 0}


RCT_EXPORT_METHOD(
    getVideoMetaData: (NSString*) filePath
    resolver: (RCTPromiseResolveBlock) resolve
    rejecter: (RCTPromiseRejectBlock) reject) {
    @try {
        [ImageCompressor getAbsoluteVideoPath:filePath completionHandler:^(NSString *absoluteImagePath) {
            if([absoluteImagePath containsString:@"file://"])
            {
                absoluteImagePath=[absoluteImagePath stringByReplacingOccurrencesOfString:@"file://"
                                                        withString:@""];
            }
            NSFileManager *fileManager = [NSFileManager defaultManager];

              BOOL isDir;
              if (![fileManager fileExistsAtPath:absoluteImagePath isDirectory:&isDir] || isDir){
                NSError *err = [NSError errorWithDomain:@"file not found" code:-15 userInfo:nil];
                reject([NSString stringWithFormat: @"%lu", (long)err.code], err.localizedDescription, err);
                return;
              }
            NSDictionary *attrs = [fileManager attributesOfItemAtPath: absoluteImagePath error: NULL];
            UInt32 fileSize = [attrs fileSize];
            NSString *fileSizeString = [@(fileSize) stringValue];

              NSMutableDictionary *result = [NSMutableDictionary new];
              NSMutableDictionary *video = [NSMutableDictionary new];
              NSDictionary *assetOptions = @{AVURLAssetPreferPreciseDurationAndTimingKey: @YES};
              AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:absoluteImagePath] options:assetOptions];\
              AVAssetTrack *avAsset = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
              CGSize size = [avAsset naturalSize];
              NSString *extension = [[absoluteImagePath lastPathComponent] pathExtension];
              CMTime time = [asset duration];
              int seconds = ceil(time.value/time.timescale);
              [video setObject:@(size.width) forKey:@"width"];
              [video setObject:@(size.height) forKey:@"height"];
              [video setObject:extension forKey:@"extension"];
              [video setObject:fileSizeString forKey:@"size"];
              [video setObject:@(seconds) forKey:@"duration"];
              [video setObject:@(avAsset.estimatedDataRate) forKey:@"bitRate"];
          
              NSArray *keys = [NSArray arrayWithObjects:@"commonMetadata", nil];
          
              NSArray *audioTracks = [asset.tracks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
                if ([[object mediaType] isEqualToString:AVMediaTypeVideo])
                {
                  for (id formatDescription in [object formatDescriptions])
                  {
                    CMFormatDescriptionRef desc = (__bridge CMFormatDescriptionRef)formatDescription;
                    CMVideoCodecType codec = CMFormatDescriptionGetMediaSubType(desc);
                    NSString* codecString = [NSString stringWithCString:(const char *)FourCC2Str(codec) encoding:NSUTF8StringEncoding];
                    [video setObject:codecString forKey:@"codec"];
                  }
                }
                  return [object mediaType] == AVMediaTypeAudio;
              }]];
          
              [result setObject:video forKey:@"video"];
              [result setObject:@(audioTracks.count > 0) forKey:@"hasAudio"];
              
              [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
                // string keys
                for (NSString *key in [self metadatas]) {
                  NSArray *items = [AVMetadataItem metadataItemsFromArray:asset.commonMetadata
                                                                 withKey:key
                                                                keySpace:AVMetadataKeySpaceCommon];
                  for (AVMetadataItem *item in items) {
                    [result setObject:item.value forKey:key];
                  }
                }
                resolve(result);
              }];
        }];
    }
    @catch (NSException *exception) {
        reject(exception.name, exception.reason, nil);
    }
}

@end


@interface RCT_EXTERN_MODULE(VideoCompressor, RCTEventEmitter)

RCT_EXTERN_METHOD(compress:(NSString *)fileUrl
                 withOptions:(NSDictionary *)options
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(upload:(NSString *)fileUrl
                 withOptions:(NSDictionary *)options
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(activateBackgroundTask: (NSDictionary *)options
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(deactivateBackgroundTask: (NSDictionary *)options
                 withResolver:(RCTPromiseResolveBlock)resolve
                 withRejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(cancelCompression:(NSString *)uuid)

@end
