//
//  PhotoEditingViewController.m
//  FilterExtention
//
//  Created by hiraya.shingo on 2014/11/19.
//  Copyright (c) 2014年 hiraya.shingo. All rights reserved.
//

#import "PhotoEditingViewController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

static NSString * const AdjustmentFormatIdentifier = @"com.example.PhotosEditSampleApp";
static NSString * const FormatVersion = @"1.0";

@interface PhotoEditingViewController () <PHContentEditingController>

/**
 *  PHContentEditingInput
 */
@property (strong, nonatomic) PHContentEditingInput *contentEditingInput;

/**
 *  フィルタ結果出力用のUIImageView
 */
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

/**
 *  フィルタ選択用のUISegmentedControl
 */
@property (weak, nonatomic) IBOutlet UISegmentedControl *segmentedControl;

/**
 *  選択中のフィルタの名
 */
@property (copy, nonatomic) NSString *selectedFilterName;

/**
 *  最初に選択されていたフィルタ名
 */
@property (copy, nonatomic) NSString *initialFilterName;

/**
 *  CIContext
 */
@property (strong, nonatomic) CIContext *ciContext;

/**
 *  フィルタ名格納用のNSArray
 */
@property (copy, nonatomic) NSArray *filterNames;

@end

@implementation PhotoEditingViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.ciContext = [CIContext contextWithOptions:nil];
    self.filterNames = @[@"CISepiaTone", @"CIPhotoEffectChrome", @"CIPhotoEffectInstant"];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - PHContentEditingController

- (BOOL)canHandleAdjustmentData:(PHAdjustmentData *)adjustmentData
{
    return [adjustmentData.formatIdentifier isEqualToString:AdjustmentFormatIdentifier] && [adjustmentData.formatVersion isEqualToString:FormatVersion];
}

- (void)startContentEditingWithInput:(PHContentEditingInput *)contentEditingInput placeholderImage:(UIImage *)placeholderImage
{
    self.contentEditingInput = contentEditingInput;
    switch (self.contentEditingInput.mediaType) {
        case PHAssetMediaTypeImage:
            self.imageView.image = self.contentEditingInput.displaySizeImage;
            break;
        default:
            break;
    }
    
    NSString *filterName;
    
    // Load adjustment data, if any
    @try {
        PHAdjustmentData *adjustmentData = contentEditingInput.adjustmentData;
        if (adjustmentData) {
            filterName = [NSKeyedUnarchiver unarchiveObjectWithData:adjustmentData.data];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception decoding adjustment data: %@", exception);
    }
    
    if (!filterName) {
        self.selectedFilterName = self.filterNames[0];
    } else {
        self.selectedFilterName = filterName;
    }
    
    self.initialFilterName = self.selectedFilterName;
    self.segmentedControl.selectedSegmentIndex = [self.filterNames indexOfObject:self.selectedFilterName];
}

- (void)finishContentEditingWithCompletionHandler:(void (^)(PHContentEditingOutput *))completionHandler
{
    // バックグラウンドキュー上でレンダリングと生成物作成を行う
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        if (self.contentEditingInput.mediaType == PHAssetMediaTypeImage) {
            // フルサイズのイメージを取得
            NSURL *url = [self.contentEditingInput fullSizeImageURL];
            int orientation = [self.contentEditingInput fullSizeImageOrientation];
            CIImage *inputImage = [CIImage imageWithContentsOfURL:url options:nil];
            inputImage = [inputImage imageByApplyingOrientation:orientation];
            
            // フィルターを適用、NSDataを作成
            CIFilter *filter = [CIFilter filterWithName:self.selectedFilterName];
            [filter setDefaults];
            [filter setValue:inputImage forKey:kCIInputImageKey];
            CIImage *outputImage = [filter outputImage];
            
            CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
            UIImage *transformedImage = [UIImage imageWithCGImage:cgImage];
            NSData *renderedJPEGData = UIImageJPEGRepresentation(transformedImage, 0.9f);
            
            // PHAdjustmentDataを作成
            NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:self.selectedFilterName];
            PHAdjustmentData *adjustmentData = [[PHAdjustmentData alloc] initWithFormatIdentifier:AdjustmentFormatIdentifier formatVersion:FormatVersion data:archivedData];
            
            // PHContentEditingOutputを作成、指定URLにjpegファイルを書き出し
            PHContentEditingOutput *contentEditingOutput = [[PHContentEditingOutput alloc] initWithContentEditingInput:self.contentEditingInput];
            [renderedJPEGData writeToURL:[contentEditingOutput renderedContentURL] atomically:YES];
            [contentEditingOutput setAdjustmentData:adjustmentData];
            
            completionHandler(contentEditingOutput);
        }
    });
}

- (BOOL)shouldShowCancelConfirmation
{
    BOOL shouldShowCancelConfirmation = NO;
    
    if (self.selectedFilterName != self.initialFilterName) {
        shouldShowCancelConfirmation = YES;
    }
    
    return shouldShowCancelConfirmation;
}

- (void)cancelContentEditing
{
    // Clean up temporary files, etc.
    // May be called after finishContentEditingWithCompletionHandler: while you prepare output.
}

#pragma mark - Action methods

/**
 *  UISegmentedControlのアクションハンドラ
 *
 *  @param sender UISegmentedControl
 */
- (IBAction)changedSegmentedControlValue:(id)sender
{
    UISegmentedControl *segmentedControl = (UISegmentedControl *)sender;
    self.selectedFilterName = self.filterNames[segmentedControl.selectedSegmentIndex];
}

#pragma mark - private methods

/**
 *  selectedFilterNameプロパティのセッター
 *
 *  @param selectedFilterName フィルタ名
 */
- (void)setSelectedFilterName:(NSString *)selectedFilterName
{
    _selectedFilterName = selectedFilterName;
    self.imageView.image = [self transformedImage:self.contentEditingInput.displaySizeImage];
}

/**
 *  UIImageにフィルタをかけて返却する
 *
 *  @param image  フィルタを適用対象のUIImage
 *
 *  @return フィルタ適用後のUIImage
 */
- (UIImage *)transformedImage:(UIImage *)image
{
    CIFilter *filter = [CIFilter filterWithName:self.selectedFilterName];
    
    CIImage *inputImage = [CIImage imageWithCGImage:image.CGImage];
    int orientation = [self orientationFromImageOrientation:image.imageOrientation];
    inputImage = [inputImage imageByApplyingOrientation:orientation];
    
    [filter setValue:inputImage forKey:kCIInputImageKey];
    CIImage *outputImage = filter.outputImage;
    
    CGImageRef cgImage = [self.ciContext createCGImage:outputImage fromRect:outputImage.extent];
    UIImage *transformedImage = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    
    return transformedImage;
}

/**
 *  UIImageOrientationからint型へ変換する
 *
 *  @param imageOrientation UIImageOrientation
 *
 *  @return int型のOrientation value
 */
- (int)orientationFromImageOrientation:(UIImageOrientation)imageOrientation
{
    int orientation = 0;
    switch (imageOrientation) {
        case UIImageOrientationUp:            orientation = 1; break;
        case UIImageOrientationDown:          orientation = 3; break;
        case UIImageOrientationLeft:          orientation = 8; break;
        case UIImageOrientationRight:         orientation = 6; break;
        case UIImageOrientationUpMirrored:    orientation = 2; break;
        case UIImageOrientationDownMirrored:  orientation = 4; break;
        case UIImageOrientationLeftMirrored:  orientation = 5; break;
        case UIImageOrientationRightMirrored: orientation = 7; break;
        default: break;
    }
    return orientation;
}

@end
