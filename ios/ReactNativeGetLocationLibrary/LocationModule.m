// MIT License
//
// Copyright (c) 2019 Douglas Nassif Roma Junior
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "LocationModule.h"
#import <React/RCTLog.h>

@implementation LocationModule

RCT_EXPORT_MODULE(ReactNativeGetLocation);

NSTimer* mTimer;
CLLocationManager* mLocationManager;
RCTPromiseResolveBlock mResolve;
RCTPromiseRejectBlock mReject;
double mTimeout;
double mDesiredAccuracyMeters;

RCT_EXPORT_METHOD(getCurrentPosition: (NSDictionary*) options
                  promise: (RCTPromiseResolveBlock) resolve
                  rejecter: (RCTPromiseRejectBlock) reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [self cancelPreviousRequest];
            
            if (![CLLocationManager locationServicesEnabled]) {
                [[NSException
                  exceptionWithName:@"Unavailable"
                  reason:@"Location service is unavailable"
                  userInfo:nil]
                 raise];
            }
            
            bool enableHighAccuracy = [RCTConvert BOOL:options[@"enableHighAccuracy"]];
            double timeout = [RCTConvert double:options[@"timeout"]];
            double desiredAccuracyMeters = MAX([RCTConvert double:options[@"desiredAccuracy"]], DBL_MAX);
            
            CLLocationManager *locationManager = [[CLLocationManager alloc] init];
            locationManager.delegate = self;
            locationManager.distanceFilter = kCLDistanceFilterNone;
            locationManager.desiredAccuracy = enableHighAccuracy ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters;
            
            mResolve = resolve;
            mReject = reject;
            mLocationManager = locationManager;
            mTimeout = timeout;
            mDesiredAccuracyMeters = desiredAccuracyMeters;
            
            if ([self isAuthorized]) {
                [self startUpdatingLocation];
            } else {
                [locationManager requestWhenInUseAuthorization];
            }
        }
        @catch (NSException *exception) {
            NSMutableDictionary * info = [NSMutableDictionary dictionary];
            [info setValue:exception.name forKey:@"ExceptionName"];
            [info setValue:exception.reason forKey:@"ExceptionReason"];
            [info setValue:exception.callStackReturnAddresses forKey:@"ExceptionCallStackReturnAddresses"];
            [info setValue:exception.callStackSymbols forKey:@"ExceptionCallStackSymbols"];
            [info setValue:exception.userInfo forKey:@"ExceptionUserInfo"];
            
            NSError *error = [[NSError alloc] initWithDomain:@"Location not available." code:1 userInfo:info];
            reject(@"UNAVAILABLE", @"Location not available", error);
        }
    });
}

RCT_EXPORT_METHOD(openAppSettings: (RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            [SettingsUtil openAppSettings];
            resolve(nil);
        }
        @catch (NSException *exception) {
            NSMutableDictionary * info = [NSMutableDictionary dictionary];
            [info setValue:exception.name forKey:@"ExceptionName"];
            [info setValue:exception.reason forKey:@"ExceptionReason"];
            [info setValue:exception.callStackReturnAddresses forKey:@"ExceptionCallStackReturnAddresses"];
            [info setValue:exception.callStackSymbols forKey:@"ExceptionCallStackSymbols"];
            [info setValue:exception.userInfo forKey:@"ExceptionUserInfo"];
            
            NSError *error = [[NSError alloc] initWithDomain:@"openAppSettings" code:0 userInfo:info];
            reject(@"openAppSettings", @"Could not open settings.", error);
        }
    });
}

- (void) locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (mResolve == nil) {
        return;
    }

    for (CLLocation* location in locations) {
        if (@(location.horizontalAccuracy).doubleValue <= mDesiredAccuracyMeters) {
            // Found one that's accurate enough, accept it and cancel updates/timeout
            [manager stopUpdatingLocation];
            if (mTimer != nil) {
                [mTimer invalidate];
            }

            NSDictionary* locationResult = @{
                @"latitude": @(location.coordinate.latitude),
                @"longitude": @(location.coordinate.longitude),
                @"altitude": @(location.altitude),
                @"speed": @(location.speed),
                @"accuracy": @(location.horizontalAccuracy),
                @"time": @(location.timestamp.timeIntervalSince1970 * 1000),
                @"verticalAccuracy": @(location.verticalAccuracy),
                @"course": @(location.course),
            };
        
            mResolve(locationResult);
            [self clearReferences];
            return;
        }
    }
}

- (void) locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [manager stopUpdatingLocation];
    if (mTimer != nil) {
        [mTimer invalidate];
    }
    if (mReject != nil) {
        mReject(@"UNAVAILABLE", @"Location not available", error);
    }
    [self clearReferences];
}

- (void) runTimeout:(id)sender {
    if (mTimer != nil) {
        [mTimer invalidate];
    }
    if (mLocationManager != nil) {
        [mLocationManager stopUpdatingLocation];
    }
    if (mReject != nil) {
        mReject(@"TIMEOUT", @"Location timed out", nil);
    }
    [self clearReferences];
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if ([self isAuthorized]) {
        [self startUpdatingLocation];
    } else if ([self isAuthorizationDenied]) {
        mReject(@"UNAUTHORIZED", @"Authorization denied", nil);
        [self clearReferences];
    }
}

- (void) clearReferences {
    mResolve = nil;
    mReject = nil;
    mLocationManager = nil;
    mTimer = nil;
    mTimeout = 0;
}

- (void) cancelPreviousRequest {
    if (mLocationManager != nil) {
        [mLocationManager stopUpdatingLocation];
        if (mReject != nil) {
            mReject(@"CANCELLED", @"Location cancelled by another request", nil);
        }
    }
    [self clearReferences];
}

- (void) startUpdatingLocation {
    [mLocationManager startUpdatingLocation];
    
    if (mTimeout > 0) {
        NSTimeInterval timeoutInterval = mTimeout / 1000.0;
        mTimer = [NSTimer scheduledTimerWithTimeInterval:timeoutInterval
                                                  target:self
                                                selector:@selector(runTimeout:)
                                                userInfo:nil
                                                 repeats:NO];
    }
}

- (BOOL) isAuthorizationDenied {
    int authorizationStatus = [CLLocationManager authorizationStatus];
    
    return authorizationStatus == kCLAuthorizationStatusDenied;
}

- (BOOL) isAuthorized {
    int authorizationStatus = [CLLocationManager authorizationStatus];
    
    return authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse
    || authorizationStatus == kCLAuthorizationStatusAuthorizedAlways;
}

@end
