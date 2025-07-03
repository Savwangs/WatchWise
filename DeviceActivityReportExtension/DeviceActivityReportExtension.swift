//
//  DeviceActivityReportExtension.swift
//  DeviceActivityReportExtension
//
//  Created by Savir Wangoo on 7/2/25.
//

import DeviceActivity
import SwiftUI

@main
struct DeviceActivityReportMain: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        // Create a report for each DeviceActivityReport.Context that your app supports.
        TotalActivityReport { totalActivity in
            TotalActivityView(totalActivity: totalActivity)
        }
        
        // App usage monitoring report
        AppUsageReport { appUsage in
            TotalActivityView(totalActivity: appUsage)
        }
        
        // New app detection report
        NewAppDetectionReport { newApps in
            TotalActivityView(totalActivity: newApps)
        }
    }
}
