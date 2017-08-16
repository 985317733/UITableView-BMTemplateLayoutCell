//
//  UITableView+BMTemplateLayoutCell.m
//
//  Copyright © 2017年 https://github.com/asiosldh/UITableView-BMTemplateLayoutCell All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "UITableView+BMTemplateLayoutCell.h"
#import <objc/runtime.h>

/**
 交换2个方法的调用
 
 @param class class
 @param originalSelector originalSelector
 @param swizzledSelector swizzledSelector
 */
void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    // 1.获取旧 Method
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    // 2.获取新 Method
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    // 3.交换方法
    if (class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))) {
        class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

CGFloat height(NSNumber *value) {
#if CGFLOAT_IS_DOUBLE
    return value.doubleValue;
#else
    return value.floatValue;
#endif
}

@interface UITableView ()

@property (strong, nonatomic, readonly) NSMutableDictionary *portraitCacheCellHeightMutableDictionary;     ///< portraitCacheCellHeightMutableDictionary
@property (strong, nonatomic, readonly) NSMutableDictionary *landscapeCacheCellHeightMutableDictionary;    ///< landscapeCacheCellHeightMutableDictionary
@property (strong, nonatomic, readonly) NSMutableDictionary *portraitCacheKeyCellHeightMutableDictionary;  ///< portraitCacheKeyCellHeightMutableDictionary
@property (strong, nonatomic, readonly) NSMutableDictionary *landscapeCacheKeyCellHeightMutableDictionary; ///< landscapeCacheKeyCellHeightMutableDictionary
@property (strong, nonatomic, readonly) NSMutableDictionary *reusableCellWithIdentifierMutableDictionary;  ///< reusableCellWithIdentifierMutableDictionary

@end

@implementation UITableView (BMTemplateLayoutCell)

- (UIView *)bm_tempViewCellWithCellClass:(Class)clas {
    // 创建新的重用标识
    NSString *noReuseIdentifier = [NSString stringWithFormat:@"noReuse%@", NSStringFromClass(clas.class)];

    NSString *noReuseIdentifierChar = self.reusableCellWithIdentifierMutableDictionary[noReuseIdentifier];
    if (!noReuseIdentifierChar) {
        noReuseIdentifierChar = noReuseIdentifier;
        self.reusableCellWithIdentifierMutableDictionary[noReuseIdentifier] = noReuseIdentifier;
    }
    // 取特定的重用标识是否绑定的Cell
    UIView *tempView = objc_getAssociatedObject(self, (__bridge const void *)(noReuseIdentifierChar));
    if (!tempView) {
        // 没有绑定就创建
        NSString *path = [[NSBundle mainBundle] pathForResource:NSStringFromClass(clas.class) ofType:@"nib"];
        UITableViewCell *noCacheCell = nil;
        if (path.length) {
            noCacheCell = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass(clas.class) owner:nil options:nil] firstObject];
            [noCacheCell setValue:noReuseIdentifier forKey:@"reuseIdentifier"];
        } else {
            noCacheCell = [[clas alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:noReuseIdentifier];
        }
        // 绑定起来
        tempView = [UIView new];
        [tempView addSubview:noCacheCell];
        objc_setAssociatedObject(self, (__bridge const void *)(noReuseIdentifierChar), tempView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"创建cell 这个 cell 不参与重用 ---- %p", noCacheCell);
    }
    return tempView;
}

- (CGFloat)bm_layoutIfNeededCellWith:(UITableViewCell *)cell configuration:(BMLayoutCellConfigurationBlock)configuration {
    // 不存在就布局一下，在获取高度进行缓存
    cell.superview.frame = CGRectMake(0, 0, self.frame.size.width, 0);
    cell.frame = CGRectMake(0, 0, self.frame.size.width, 0);
    configuration(cell);
    [cell.superview layoutIfNeeded];
    __block CGFloat maxY = 0;
    [cell.contentView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (maxY <  CGRectGetMaxY(obj.frame)) {
            maxY = CGRectGetMaxY(obj.frame);
        }
    }];
    maxY += .5;
    return maxY;
}


- (CGFloat)bm_heightForCellWithCellClass:(Class)clas configuration:(BMLayoutCellConfigurationBlock)configuration {
    if (!clas || configuration) {
        return 0;
    }
    UIView *tempView = [self bm_tempViewCellWithCellClass:clas];
    return [self bm_layoutIfNeededCellWith:tempView.subviews[0] configuration:configuration];
}

- (CGFloat)bm_heightForCellWithCellClass:(Class)clas
                        cacheByIndexPath:(NSIndexPath *)indexPath
                           configuration:(BMLayoutCellConfigurationBlock)configuration {
    if (!clas || !configuration) {
        return 0;
    }
    if (!indexPath) {
       return [self bm_heightForCellWithCellClass:clas configuration:configuration];
    }
    NSString *key = [NSString stringWithFormat:@"%ld-%ld", (long)indexPath.section, (long)indexPath.row];
    BOOL isPortrait = UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation);
    NSNumber *heightValue = (isPortrait ? self.portraitCacheCellHeightMutableDictionary :  self.landscapeCacheCellHeightMutableDictionary)[key];
    if (heightValue) {
        return height(heightValue);
    }
    UIView *tempView = [self bm_tempViewCellWithCellClass:clas];
    CGFloat height = [self bm_layoutIfNeededCellWith:tempView.subviews[0] configuration:configuration];
    (isPortrait ? self.portraitCacheCellHeightMutableDictionary :  self.landscapeCacheCellHeightMutableDictionary)[key] = @(height);
    return height;
}

- (CGFloat)bm_heightForCellWithCellClass:(Class)clas cacheByKey:(NSString *)key configuration:(BMLayoutCellConfigurationBlock)configuration {
    if (!clas || !configuration) {
        return 0;
    }
    if (!key || key.length) {
        return [self bm_heightForCellWithCellClass:clas configuration:configuration];
    }
    BOOL isPortrait = UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation);
    NSNumber *heightValue = (isPortrait ? self.portraitCacheKeyCellHeightMutableDictionary :  self.landscapeCacheKeyCellHeightMutableDictionary)[key];
    if (heightValue) {
        return height(heightValue);
    }
    UIView *tempView = [self bm_tempViewCellWithCellClass:clas];
    CGFloat height = [self bm_layoutIfNeededCellWith:tempView.subviews[0] configuration:configuration];
    (isPortrait ? self.portraitCacheKeyCellHeightMutableDictionary :  self.landscapeCacheKeyCellHeightMutableDictionary)[key] = @(height);
    return height;
}

- (NSMutableDictionary *)portraitCacheCellHeightMutableDictionary {
    NSMutableDictionary *portraitCacheCellHeightMutableDictionary = objc_getAssociatedObject(self, _cmd);
    if (!portraitCacheCellHeightMutableDictionary) {
        portraitCacheCellHeightMutableDictionary = @{}.mutableCopy;
        objc_setAssociatedObject(self, _cmd, portraitCacheCellHeightMutableDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return portraitCacheCellHeightMutableDictionary;
}

- (NSMutableDictionary *)landscapeCacheCellHeightMutableDictionary {
    NSMutableDictionary *landscapeCacheCellHeightMutableDictionary = objc_getAssociatedObject(self, _cmd);
    if (!landscapeCacheCellHeightMutableDictionary) {
        landscapeCacheCellHeightMutableDictionary = @{}.mutableCopy;
        objc_setAssociatedObject(self, _cmd, landscapeCacheCellHeightMutableDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return landscapeCacheCellHeightMutableDictionary;
}

- (NSMutableDictionary *)reusableCellWithIdentifierMutableDictionary {
    NSMutableDictionary *reusableCellWithIdentifierMutableDictionary = objc_getAssociatedObject(self, _cmd);
    if (!reusableCellWithIdentifierMutableDictionary) {
        reusableCellWithIdentifierMutableDictionary = @{}.mutableCopy;
        objc_setAssociatedObject(self, _cmd, reusableCellWithIdentifierMutableDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return reusableCellWithIdentifierMutableDictionary;
}

- (NSMutableDictionary *)portraitCacheKeyCellHeightMutableDictionary {
    NSMutableDictionary *portraitCacheKeyCellHeightMutableDictionary = objc_getAssociatedObject(self, _cmd);
    if (!portraitCacheKeyCellHeightMutableDictionary) {
        portraitCacheKeyCellHeightMutableDictionary = @{}.mutableCopy;
        objc_setAssociatedObject(self, _cmd, portraitCacheKeyCellHeightMutableDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return portraitCacheKeyCellHeightMutableDictionary;
}

- (NSMutableDictionary *)landscapeCacheKeyCellHeightMutableDictionary {
    NSMutableDictionary *landscapeCacheKeyCellHeightMutableDictionary = objc_getAssociatedObject(self, _cmd);
    if (!landscapeCacheKeyCellHeightMutableDictionary) {
        landscapeCacheKeyCellHeightMutableDictionary = @{}.mutableCopy;
        objc_setAssociatedObject(self, _cmd, landscapeCacheKeyCellHeightMutableDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return landscapeCacheKeyCellHeightMutableDictionary;
}

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SEL selectors[] = {
            @selector(reloadData),
            @selector(insertSections:withRowAnimation:),
            @selector(deleteSections:withRowAnimation:),
            @selector(reloadSections:withRowAnimation:),
            @selector(moveSection:toSection:),
            @selector(insertRowsAtIndexPaths:withRowAnimation:),
            @selector(deleteRowsAtIndexPaths:withRowAnimation:),
            @selector(reloadRowsAtIndexPaths:withRowAnimation:),
            @selector(moveRowAtIndexPath:toIndexPath:)
        };
        for (NSUInteger index = 0; index < sizeof(selectors) / sizeof(SEL); ++index) {
            SEL originalSelector = selectors[index];
            SEL swizzledSelector = NSSelectorFromString([@"bm_" stringByAppendingString:NSStringFromSelector(originalSelector)]);
            swizzleMethod(self.class, originalSelector, swizzledSelector);
        }
    });
}

- (void)bm_reloadData {
    [self.portraitCacheCellHeightMutableDictionary  removeAllObjects];
    [self.landscapeCacheCellHeightMutableDictionary removeAllObjects];
    [self bm_reloadData];
}

- (void)bm_insertSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    // 待优化
    [self.portraitCacheCellHeightMutableDictionary  removeAllObjects];
    [self.landscapeCacheCellHeightMutableDictionary removeAllObjects];
    [self bm_insertSections:sections withRowAnimation:animation];
}

- (void)bm_deleteSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    // 待优化
    [self.portraitCacheCellHeightMutableDictionary  removeAllObjects];
    [self.landscapeCacheCellHeightMutableDictionary removeAllObjects];
    [self bm_deleteSections:sections withRowAnimation:animation];
}

- (void)bm_reloadSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    // 将需要刷新的的 section 的高度缓存清除
    [sections enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        NSInteger row = [self.dataSource tableView:self numberOfRowsInSection:idx];
        while (row--) {
            NSString *cacheID = [NSString stringWithFormat:@"%ld-%ld", (long)idx, (long)row];
            [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:cacheID];
            [self.landscapeCacheCellHeightMutableDictionary removeObjectForKey:cacheID];
        }
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Header:%ld", idx]];
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Footer:%ld", idx]];
        
        [self.landscapeCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Header:%ld", idx]];
        [self.landscapeCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Footer:%ld", idx]];
        
    }];
    [self bm_reloadSections:sections withRowAnimation:animation];
}

- (void)bm_moveSection:(NSInteger)section toSection:(NSInteger)newSection {
    // 待优化
    {
        NSInteger row = [self.dataSource tableView:self numberOfRowsInSection:section];
        while (row--) {
            NSString *cacheID = [NSString stringWithFormat:@"%ld-%ld", (long)section, (long)row];
            [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:cacheID];
            [self.landscapeCacheCellHeightMutableDictionary removeObjectForKey:cacheID];
        }
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Header:%ld", section]];
        [self.landscapeCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Header:%ld", section]];
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Footer:%ld", section]];
        [self.landscapeCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Footer:%ld", section]];
    }
    {
        NSInteger row = [self.dataSource tableView:self numberOfRowsInSection:newSection];
        while (row--) {
            NSString *cacheID = [NSString stringWithFormat:@"%ld-%ld", (long)newSection, (long)row];
            [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:cacheID];
            [self.landscapeCacheCellHeightMutableDictionary removeObjectForKey:cacheID];
        }
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Header:%ld", newSection]];
        [self.landscapeCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Header:%ld", newSection]];
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Footer:%ld", newSection]];
        [self.landscapeCacheCellHeightMutableDictionary  removeObjectForKey:[NSString stringWithFormat:@"Footer:%ld", newSection]];
    }
    [self bm_moveSection:section toSection:newSection];
}

- (void)bm_insertRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation {
    // 待优化
    [self.portraitCacheCellHeightMutableDictionary  removeAllObjects];
    [self.landscapeCacheCellHeightMutableDictionary removeAllObjects];
    [self bm_insertRowsAtIndexPaths:indexPaths withRowAnimation:animation];
}

- (void)bm_deleteRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation {
    // 待优化
    [self.portraitCacheCellHeightMutableDictionary  removeAllObjects];
    [self.landscapeCacheCellHeightMutableDictionary removeAllObjects];
    [self bm_deleteRowsAtIndexPaths:indexPaths withRowAnimation:animation];
}

- (void)bm_reloadRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation {
    // 将需要刷新的 indexPath 的高度缓存清除
    [indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *cacheID = [NSString stringWithFormat:@"%ld-%ld", (long)obj.section, (long)obj.row];
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:cacheID];
        [self.landscapeCacheCellHeightMutableDictionary removeObjectForKey:cacheID];
    }];
    [self bm_reloadRowsAtIndexPaths:indexPaths withRowAnimation:animation];
}

- (void)bm_moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    // 待优化
    {
        NSString *cacheID = [NSString stringWithFormat:@"%ld-%ld", (long)sourceIndexPath.section, (long)sourceIndexPath.row];
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:cacheID];
        [self.landscapeCacheCellHeightMutableDictionary removeObjectForKey:cacheID];
    }
    {
        NSString *cacheID = [NSString stringWithFormat:@"%ld-%ld", (long)destinationIndexPath.section, (long)destinationIndexPath.row];
        [self.portraitCacheCellHeightMutableDictionary  removeObjectForKey:cacheID];
        [self.landscapeCacheCellHeightMutableDictionary removeObjectForKey:cacheID];
    }
    [self bm_moveRowAtIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
}

@end

@implementation UITableView (BMTemplateLayoutHeaderFooterView)

- (CGFloat)bm_heightForHeaderFooterViewWithWithHeaderFooterViewClass:(Class)clas configuration:(BMLayoutHeaderFooterViewConfigurationBlock)configuration {
    // 没有缓存创建临时View来布局获取高度
    UIView *tempView = [self bm_tempViewHeaderFooterViewWithHeaderFooterViewClass:clas];
    // 布局获取高度
    return [self bm_layoutIfNeededHeaderFooterViewWith:tempView.subviews[0] configuration:configuration];
}

- (CGFloat)bm_heightForHeaderFooterViewWithWithHeaderFooterViewClass:(Class)clas isHeaderView:(BOOL)isHeaderView section:(NSInteger)section configuration:(BMLayoutHeaderFooterViewConfigurationBlock)configuration {
    NSString *key = [NSString stringWithFormat:@"%@:%ld", isHeaderView ? @"Header" : @ "Footer" ,section];
    NSNumber *heightValue = (UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation) ? self.portraitCacheCellHeightMutableDictionary :  self.landscapeCacheCellHeightMutableDictionary)[key];
    // 有缓存就直接返回
    if (heightValue) {
        return height(heightValue);
    }
    // 没有缓存创建临时View来布局获取高度
    UIView *tempView = [self bm_tempViewHeaderFooterViewWithHeaderFooterViewClass:clas];
    
    // 布局获取高度
    CGFloat height = [self bm_layoutIfNeededHeaderFooterViewWith:tempView.subviews[0] configuration:configuration];
    
    // 缓存起来
    (UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation) ? self.portraitCacheCellHeightMutableDictionary :  self.landscapeCacheCellHeightMutableDictionary)[key] = @(height);
    return height;
}

- (CGFloat)bm_heightForHeaderFooterViewWithWithHeaderFooterViewClass:(Class)clas cacheByKey:(NSString *)key configuration:(BMLayoutHeaderFooterViewConfigurationBlock)configuration {
    NSNumber *heightValue = (UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation) ? self.portraitCacheKeyCellHeightMutableDictionary :  self.landscapeCacheKeyCellHeightMutableDictionary)[key];
    // 有缓存就直接返回
    if (heightValue) {
        return height(heightValue);
    }
    // 没有缓存创建临时View来布局获取高度
    UIView *tempView = [self bm_tempViewHeaderFooterViewWithHeaderFooterViewClass:clas];
    
    // 布局获取高度
    CGFloat height = [self bm_layoutIfNeededHeaderFooterViewWith:tempView.subviews[0] configuration:configuration];
    
    // 缓存起来
    (UIDeviceOrientationIsPortrait([UIDevice currentDevice].orientation) ? self.portraitCacheKeyCellHeightMutableDictionary :  self.landscapeCacheKeyCellHeightMutableDictionary)[key] = @(height);
    return height;
}


- (UIView *)bm_tempViewHeaderFooterViewWithHeaderFooterViewClass:(Class)clas {
    NSString *noReuseIdentifier = [NSString stringWithFormat:@"noReuse%@", NSStringFromClass(clas.class)];
    NSString *noReuseIdentifierChar = self.reusableCellWithIdentifierMutableDictionary[noReuseIdentifier];
    if (!noReuseIdentifierChar) {
        noReuseIdentifierChar = noReuseIdentifier;
        self.reusableCellWithIdentifierMutableDictionary[noReuseIdentifier] = noReuseIdentifier;
    }
    // 取特定的重用标识是否绑定的Cell
    UIView *tempView = objc_getAssociatedObject(self, (__bridge const void *)(noReuseIdentifierChar));
    if (!tempView) {
        // 没有绑定就创建
        UITableViewHeaderFooterView *noCachetableViewHeaderFooterView = nil;
        NSString *path = [[NSBundle mainBundle] pathForResource:NSStringFromClass(clas.class) ofType:@"nib"];
        if (path.length) {
            noCachetableViewHeaderFooterView = [[[NSBundle mainBundle] loadNibNamed:NSStringFromClass(clas.class) owner:nil options:nil] firstObject];
            [noCachetableViewHeaderFooterView setValue:noReuseIdentifier forKey:@"reuseIdentifier"];
        } else {
            noCachetableViewHeaderFooterView = [[clas alloc] initWithReuseIdentifier:noReuseIdentifier];
        }
        // 绑定起来
        tempView = [UIView new];
        [tempView addSubview:noCachetableViewHeaderFooterView];
        objc_setAssociatedObject(self, (__bridge const void *)(noReuseIdentifierChar), tempView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"创建cell 这个 noCachetableViewHeaderFooterView 不参与重用 ---- %p", tempView);
    }
    return tempView;
}

- (CGFloat)bm_layoutIfNeededHeaderFooterViewWith:(UITableViewHeaderFooterView *)tableViewHeaderFooterView configuration:(BMLayoutHeaderFooterViewConfigurationBlock)configuration {
    // 不存在就布局一下，在获取高度进行缓存
    tableViewHeaderFooterView.superview.frame = CGRectMake(0, 0, self.frame.size.width, 0);
    tableViewHeaderFooterView.frame = CGRectMake(0, 0, self.frame.size.width, 0);
    configuration(tableViewHeaderFooterView);
    [tableViewHeaderFooterView.superview layoutIfNeeded];
    __block CGFloat maxY = 0;
    [tableViewHeaderFooterView.contentView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (maxY <  CGRectGetMaxY(obj.frame)) {
            maxY = CGRectGetMaxY(obj.frame);
        }
    }];
    return maxY;
}

@end