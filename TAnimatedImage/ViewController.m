//
//  ViewController.m
//  TAnimatedImage
//
//  Created by liqi on 2018/3/14.
//  Copyright © 2018年 apple. All rights reserved.
//

#import "ViewController.h"
#import "TAnimatedImage.h"
#import "TAnimatedImageView.h"

@interface ViewController ()

@property (nonatomic, strong) TAnimatedImageView *imageView1;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    if (!self.imageView1) {
        self.imageView1 = [[TAnimatedImageView alloc] init];
        self.imageView1.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView1.clipsToBounds = YES;
    }
    [self.view addSubview:self.imageView1];
    self.imageView1.frame = CGRectMake(0.0, 120.0, self.view.bounds.size.width, 447.0);
    
    NSURL *url1 = [[NSBundle mainBundle] URLForResource:@"rock" withExtension:@"gif"];
    NSData *data1 = [NSData dataWithContentsOfURL:url1];
    UIImage *image = [[UIImage alloc] initWithData:data1];
//    self.imageView1.image = image;
    TAnimatedImage *animatedImage1 = [TAnimatedImage animatedImageWithGIFData:data1];
    self.imageView1.animatedImage = animatedImage1;
}


- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    static BOOL isStop = YES;
    if (isStop) {
        [self.imageView1 stopAnimating];
        isStop = NO;
    }
    else {
        [self.imageView1 startAnimating];
        isStop = YES;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
