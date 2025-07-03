import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();

// Cloud Function to clean up expired pairing codes
export const cleanupExpiredPairingCodes = functions.pubsub
  .schedule('every 10 minutes')
  .onRun(async (context) => {
    try {
      console.log('🔄 Starting cleanup of expired pairing codes...');
      
      const now = admin.firestore.Timestamp.now();
      
      // Query for expired pairing codes that haven't been marked as expired
      const expiredCodesQuery = db.collection('pairingRequests')
        .where('expiresAt', '<', now)
        .where('isExpired', '==', false);
      
      const snapshot = await expiredCodesQuery.get();
      
      if (snapshot.empty) {
        console.log('✅ No expired codes found');
        return null;
      }
      
      console.log(`📝 Found ${snapshot.size} expired codes to clean up`);
      
      // Batch update to mark all expired codes
      const batch = db.batch();
      let processedCount = 0;
      
      snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          isExpired: true,
          cleanedUpAt: now
        });
        processedCount++;
      });
      
      await batch.commit();
      
      console.log(`✅ Successfully cleaned up ${processedCount} expired pairing codes`);
      
      return null;
    } catch (error) {
      console.error('❌ Error cleaning up expired pairing codes:', error);
      throw error;
    }
  });

// Cloud Function to clean up old pairing requests (older than 24 hours)
export const cleanupOldPairingRequests = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => {
    try {
      console.log('🔄 Starting cleanup of old pairing requests...');
      
      const twentyFourHoursAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 24 * 60 * 60 * 1000)
      );
      
      // Query for old pairing requests (older than 24 hours)
      const oldRequestsQuery = db.collection('pairingRequests')
        .where('createdAt', '<', twentyFourHoursAgo);
      
      const snapshot = await oldRequestsQuery.get();
      
      if (snapshot.empty) {
        console.log('✅ No old pairing requests found');
        return null;
      }
      
      console.log(`📝 Found ${snapshot.size} old pairing requests to delete`);
      
      // Batch delete old requests
      const batch = db.batch();
      let deletedCount = 0;
      
      snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
        deletedCount++;
      });
      
      await batch.commit();
      
      console.log(`✅ Successfully deleted ${deletedCount} old pairing requests`);
      
      return null;
    } catch (error) {
      console.error('❌ Error cleaning up old pairing requests:', error);
      throw error;
    }
  });

// Cloud Function to handle device activity monitoring
export const updateDeviceActivity = functions.https.onCall(async (data, context) => {
  try {
    // Check if user is authenticated
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    
    const userId = context.auth.uid;
    const { deviceInfo, activityType } = data;
    
    console.log(`📱 Updating device activity for user: ${userId}, type: ${activityType}`);
    
    // Handle different activity types
    switch (activityType) {
      case 'app_shutdown':
        // App is closing gracefully - mark as normal closure
        await handleAppShutdown(userId, deviceInfo);
        break;
        
      case 'app_background':
        // App is going to background - update normally
        await handleAppBackground(userId, deviceInfo);
        break;
        
      case 'heartbeat':
        // Normal heartbeat - update relationships
        await handleHeartbeat(userId, deviceInfo);
        break;
        
      default:
        // Other activities - update normally
        await handleNormalActivity(userId, deviceInfo, activityType);
        break;
    }
    
    return { success: true };
  } catch (error) {
    console.error('❌ Error updating device activity:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update device activity');
  }
});

// Handle graceful app shutdown
async function handleAppShutdown(userId: string, deviceInfo: any) {
  console.log(`🔄 Handling app shutdown for user: ${userId}`);
  
  // Update user's last activity
  await db.collection('users').doc(userId).update({
    lastActiveAt: admin.firestore.Timestamp.now(),
    deviceInfo: deviceInfo || null,
    lastActivityType: 'app_shutdown',
    lastGracefulShutdown: admin.firestore.Timestamp.now()
  });
  
  // Update parent-child relationships
  const relationshipsQuery = db.collection('parentChildRelationships')
    .where('childUserId', '==', userId)
    .where('isActive', '==', true);
  
  const relationshipsSnapshot = await relationshipsQuery.get();
  
  if (!relationshipsSnapshot.empty) {
    const batch = db.batch();
    
    relationshipsSnapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        lastSyncAt: admin.firestore.Timestamp.now(),
        childDeviceInfo: deviceInfo || null,
        lastGracefulShutdown: admin.firestore.Timestamp.now(),
        missedHeartbeats: 0, // Reset missed heartbeats
        isNormalClosure: true
      });
    });
    
    await batch.commit();
    console.log(`✅ Updated ${relationshipsSnapshot.size} parent-child relationships with graceful shutdown`);
  }
}

// Handle app background
async function handleAppBackground(userId: string, deviceInfo: any) {
  console.log(`🔄 Handling app background for user: ${userId}`);
  
  // Update user's last activity
  await db.collection('users').doc(userId).update({
    lastActiveAt: admin.firestore.Timestamp.now(),
    deviceInfo: deviceInfo || null,
    lastActivityType: 'app_background'
  });
  
  // Update parent-child relationships
  const relationshipsQuery = db.collection('parentChildRelationships')
    .where('childUserId', '==', userId)
    .where('isActive', '==', true);
  
  const relationshipsSnapshot = await relationshipsQuery.get();
  
  if (!relationshipsSnapshot.empty) {
    const batch = db.batch();
    
    relationshipsSnapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        lastSyncAt: admin.firestore.Timestamp.now(),
        childDeviceInfo: deviceInfo || null
      });
    });
    
    await batch.commit();
    console.log(`✅ Updated ${relationshipsSnapshot.size} parent-child relationships with background state`);
  }
}

// Handle heartbeat
async function handleHeartbeat(userId: string, deviceInfo: any) {
  console.log(`💓 Handling heartbeat for user: ${userId}`);
  
  // Update user's last activity
  await db.collection('users').doc(userId).update({
    lastActiveAt: admin.firestore.Timestamp.now(),
    deviceInfo: deviceInfo || null,
    lastActivityType: 'heartbeat'
  });
  
  // Update parent-child relationships
  const relationshipsQuery = db.collection('parentChildRelationships')
    .where('childUserId', '==', userId)
    .where('isActive', '==', true);
  
  const relationshipsSnapshot = await relationshipsQuery.get();
  
  if (!relationshipsSnapshot.empty) {
    const batch = db.batch();
    
    relationshipsSnapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        lastSyncAt: admin.firestore.Timestamp.now(),
        childDeviceInfo: deviceInfo || null,
        lastHeartbeatAt: admin.firestore.Timestamp.now(),
        missedHeartbeats: 0 // Reset missed heartbeats on successful heartbeat
      });
    });
    
    await batch.commit();
    console.log(`✅ Updated ${relationshipsSnapshot.size} parent-child relationships with heartbeat`);
  }
}

// Handle normal activity
async function handleNormalActivity(userId: string, deviceInfo: any, activityType: string) {
  console.log(`📱 Handling normal activity for user: ${userId}, type: ${activityType}`);
  
  // Update user's last activity
  await db.collection('users').doc(userId).update({
    lastActiveAt: admin.firestore.Timestamp.now(),
    deviceInfo: deviceInfo || null,
    lastActivityType: activityType || 'app_opened'
  });
  
  // Update parent-child relationships
  const relationshipsQuery = db.collection('parentChildRelationships')
    .where('childUserId', '==', userId)
    .where('isActive', '==', true);
  
  const relationshipsSnapshot = await relationshipsQuery.get();
  
  if (!relationshipsSnapshot.empty) {
    const batch = db.batch();
    
    relationshipsSnapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        lastSyncAt: admin.firestore.Timestamp.now(),
        childDeviceInfo: deviceInfo || null
      });
    });
    
    await batch.commit();
    console.log(`✅ Updated ${relationshipsSnapshot.size} parent-child relationships`);
  }
}

// Cloud Function to check for inactive children and notify parents
export const checkInactiveChildren = functions.pubsub
  .schedule('every 6 hours')
  .onRun(async (context) => {
    try {
      console.log('🔄 Checking for inactive children...');
      
      const threeDaysAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 3 * 24 * 60 * 60 * 1000)
      );
      
      // Query for children who haven't been active in 3 days
      const inactiveChildrenQuery = db.collection('users')
        .where('lastActiveAt', '<', threeDaysAgo)
        .where('userType', '==', 'child');
      
      const snapshot = await inactiveChildrenQuery.get();
      
      if (snapshot.empty) {
        console.log('✅ No inactive children found');
        return null;
      }
      
      console.log(`📝 Found ${snapshot.size} inactive children`);
      
      // For each inactive child, find their parent and send notification
              for (const childDoc of snapshot.docs) {
            const childUserId = childDoc.id;
            
            // Find parent-child relationship
        const relationshipQuery = db.collection('parentChildRelationships')
          .where('childUserId', '==', childUserId)
          .where('isActive', '==', true);
        
        const relationshipSnapshot = await relationshipQuery.get();
        
        if (!relationshipSnapshot.empty) {
          const relationship = relationshipSnapshot.docs[0];
          const parentUserId = relationship.data().parentUserId;
          const childName = relationship.data().childName;
          
          // Create notification for parent
          await db.collection('notifications').add({
            parentUserId: parentUserId,
            childUserId: childUserId,
            childName: childName,
            type: 'inactivity_alert',
            title: 'Child Device Inactive',
            message: `${childName} hasn't opened WatchWise in 3 days. Please check on their device.`,
            timestamp: admin.firestore.Timestamp.now(),
            isRead: false
          });
          
          console.log(`📧 Sent inactivity notification to parent ${parentUserId} for child ${childName}`);
        }
      }
      
      return null;
    } catch (error) {
      console.error('❌ Error checking inactive children:', error);
      throw error;
    }
  });

// Cloud Function to handle device unlink
export const unlinkDevice = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
    }
    
    const { relationshipId } = data;
    const userId = context.auth.uid;
    
    console.log(`🔗 Unlinking device for relationship: ${relationshipId}`);
    
    // Get the relationship document
    const relationshipDoc = await db.collection('parentChildRelationships')
      .doc(relationshipId)
      .get();
    
    if (!relationshipDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Relationship not found');
    }
    
    const relationshipData = relationshipDoc.data()!;
    
    // Verify the user is authorized to unlink this device
    if (relationshipData.parentUserId !== userId && relationshipData.childUserId !== userId) {
      throw new functions.https.HttpsError('permission-denied', 'Not authorized to unlink this device');
    }
    
    // Update relationship status
    await relationshipDoc.ref.update({
      isActive: false,
      unlinkedAt: admin.firestore.Timestamp.now(),
      unlinkedBy: userId
    });
    
    // Update child's device pairing status
    await db.collection('users').doc(relationshipData.childUserId).update({
      isDevicePaired: false,
      pairedWithParent: admin.firestore.FieldValue.delete(),
      unlinkedAt: admin.firestore.Timestamp.now()
    });
    
    // Create notification for the other party
    const notificationData = {
      parentUserId: relationshipData.parentUserId,
      childUserId: relationshipData.childUserId,
      childName: relationshipData.childName,
      type: 'device_unlinked',
      title: 'Device Unlinked',
      message: `${relationshipData.childName}'s device has been unlinked from your account.`,
      timestamp: admin.firestore.Timestamp.now(),
      isRead: false
    };
    
    await db.collection('notifications').add(notificationData);
    
    console.log(`✅ Successfully unlinked device for relationship: ${relationshipId}`);
    
    return { success: true };
  } catch (error) {
    console.error('❌ Error unlinking device:', error);
    throw new functions.https.HttpsError('internal', 'Failed to unlink device');
  }
});

// Cloud Function to check for missed heartbeats and notify parents
export const checkMissedHeartbeats = functions.pubsub
  .schedule('every 20 minutes')
  .onRun(async (context) => {
    try {
      console.log('💓 Checking for missed heartbeats...');
      
      const twentyMinutesAgo = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - 20 * 60 * 1000)
      );
      
      // Query for child devices that haven't sent a heartbeat in 20+ minutes
      const missedHeartbeatsQuery = db.collection('parentChildRelationships')
        .where('isActive', '==', true)
        .where('lastHeartbeatAt', '<', twentyMinutesAgo);
      
      const snapshot = await missedHeartbeatsQuery.get();
      
      if (snapshot.empty) {
        console.log('✅ No missed heartbeats found');
        return null;
      }
      
      console.log(`💓 Found ${snapshot.size} relationships with missed heartbeats`);
      
      // Process each relationship with missed heartbeats
      for (const doc of snapshot.docs) {
        const relationshipData = doc.data();
        const childUserId = relationshipData.childUserId;
        const parentUserId = relationshipData.parentUserId;
        const childName = relationshipData.childName;
        const lastHeartbeatAt = relationshipData.lastHeartbeatAt;
        const currentMissedHeartbeats = relationshipData.missedHeartbeats || 0;
        
        // Calculate how many heartbeats have been missed
        const timeSinceLastHeartbeat = Date.now() - lastHeartbeatAt.toDate().getTime();
        const missedHeartbeats = Math.floor(timeSinceLastHeartbeat / (15 * 60 * 1000)); // 15 minutes per heartbeat
        
        // Only send notification if we haven't already sent one for this level
        if (missedHeartbeats > currentMissedHeartbeats) {
          // Update the missed heartbeat count
          await doc.ref.update({
            missedHeartbeats: missedHeartbeats
          });
          
          // Determine notification message based on missed heartbeats
          const [title, message] = getMissedHeartbeatMessage(missedHeartbeats, childName);
          
          // Create notification for parent
          await db.collection('notifications').add({
            parentUserId: parentUserId,
            childUserId: childUserId,
            childName: childName,
            type: 'missed_heartbeat',
            title: title,
            message: message,
            missedHeartbeats: missedHeartbeats,
            timestamp: admin.firestore.Timestamp.now(),
            isRead: false
          });
          
          console.log(`📧 Sent missed heartbeat notification to parent ${parentUserId} for child ${childName}: ${title}`);
        }
      }
      
      return null;
    } catch (error) {
      console.error('❌ Error checking missed heartbeats:', error);
      throw error;
    }
  });

// Helper function to get missed heartbeat notification message
function getMissedHeartbeatMessage(missedHeartbeats: number, childName: string): [string, string] {
  switch (missedHeartbeats) {
    case 1:
      return [
        "First Heartbeat Missed",
        `${childName}'s device missed its first heartbeat. This could indicate the app was closed or the device is having connectivity issues.`
      ];
    case 2:
      return [
        "Second Heartbeat Missed",
        `${childName}'s device has missed 2 consecutive heartbeats. The app may have been deleted or the device is turned off.`
      ];
    case 3:
    case 4:
      return [
        "Multiple Heartbeats Missed",
        `${childName}'s device has missed ${missedHeartbeats} consecutive heartbeats. Please check if the WatchWise app is still installed and running.`
      ];
    default:
      return [
        "Extended Heartbeat Failure",
        `${childName}'s device has been offline for over 5 hours. The WatchWise app may have been deleted or the device is experiencing issues.`
      ];
  }
}

// Cloud Function to process real-time screen time updates
export const processScreenTimeUpdate = functions.firestore
  .document('screenTimeData/{documentId}')
  .onWrite(async (change, context) => {
    try {
      const documentId = context.params.documentId;
      console.log(`🔄 Processing screen time update for document: ${documentId}`);
      
      if (!change.after.exists) {
        console.log('Document deleted, skipping processing');
        return null;
      }
      
      const data = change.after.data();
      const deviceId = data?.deviceId;
      const isRealtime = data?.isRealtime;
      
      if (!deviceId || !isRealtime) {
        console.log('Not a real-time update, skipping processing');
        return null;
      }
      
      // Update device activity
      await updateDeviceActivityForScreenTime(deviceId, data);
      
      // Trigger notifications if needed
      await checkAndTriggerNotifications(deviceId, data);
      
      // Update aggregations
      await updateScreenTimeAggregations(deviceId, data);
      
      console.log(`✅ Screen time update processed successfully for device: ${deviceId}`);
      
      return null;
    } catch (error) {
      console.error('❌ Error processing screen time update:', error);
      throw error;
    }
  });

// Cloud Function to aggregate screen time data daily
export const aggregateDailyScreenTime = functions.pubsub
  .schedule('0 1 * * *') // Run at 1 AM daily
  .onRun(async (context) => {
    try {
      console.log('🔄 Starting daily screen time aggregation...');
      
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const startOfDay = new Date(yesterday.getFullYear(), yesterday.getMonth(), yesterday.getDate());
      const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);
      
      // Get all screen time data from yesterday
      const snapshot = await db.collection('screenTimeData')
        .where('date', '>=', startOfDay)
        .where('date', '<', endOfDay)
        .get();
      
      if (snapshot.empty) {
        console.log('✅ No screen time data found for yesterday');
        return null;
      }
      
      console.log(`📊 Processing ${snapshot.size} screen time documents`);
      
      // Group by device
      const deviceData: { [deviceId: string]: any[] } = {};
      
      snapshot.docs.forEach(doc => {
        const data = doc.data();
        const deviceId = data.deviceId;
        
        if (!deviceData[deviceId]) {
          deviceData[deviceId] = [];
        }
        deviceData[deviceId].push(data);
      });
      
      // Process each device's data
      for (const [deviceId, documents] of Object.entries(deviceData)) {
        await aggregateDeviceScreenTime(deviceId, documents, startOfDay);
      }
      
      console.log(`✅ Daily aggregation completed for ${Object.keys(deviceData).length} devices`);
      
      return null;
    } catch (error) {
      console.error('❌ Error in daily screen time aggregation:', error);
      throw error;
    }
  });

// Cloud Function to clean up old screen time data
export const cleanupOldScreenTimeData = functions.pubsub
  .schedule('0 3 * * 0') // Run at 3 AM every Sunday
  .onRun(async (context) => {
    try {
      console.log('🔄 Starting cleanup of old screen time data...');
      
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      
      // Delete old screen time data
      const screenTimeSnapshot = await db.collection('screenTimeData')
        .where('date', '<', thirtyDaysAgo)
        .limit(500) // Process in batches
        .get();
      
      if (!screenTimeSnapshot.empty) {
        const batch = db.batch();
        screenTimeSnapshot.docs.forEach(doc => {
          batch.delete(doc.ref);
        });
        await batch.commit();
        console.log(`🗑️ Deleted ${screenTimeSnapshot.size} old screen time documents`);
      }
      
      // Delete old app usage data
      const appUsageSnapshot = await db.collection('appUsageData')
        .where('timestamp', '<', thirtyDaysAgo)
        .limit(500)
        .get();
      
      if (!appUsageSnapshot.empty) {
        const batch = db.batch();
        appUsageSnapshot.docs.forEach(doc => {
          batch.delete(doc.ref);
        });
        await batch.commit();
        console.log(`🗑️ Deleted ${appUsageSnapshot.size} old app usage documents`);
      }
      
      console.log('✅ Cleanup completed successfully');
      
      return null;
    } catch (error) {
      console.error('❌ Error in cleanup:', error);
      throw error;
    }
  });

// Helper function to update device activity
async function updateDeviceActivityForScreenTime(deviceId: string, screenTimeData: any) {
  const activityData = {
    deviceId: deviceId,
    lastScreenTimeUpdate: admin.firestore.Timestamp.now(),
    totalScreenTime: screenTimeData.totalScreenTime || 0,
    appCount: screenTimeData.appUsages?.length || 0,
    isActive: true
  };
  
  await db.collection('deviceActivity').doc(deviceId).set(activityData, { merge: true });
  console.log(`📱 Updated device activity for ${deviceId}`);
}

// Helper function to check and trigger notifications
async function checkAndTriggerNotifications(deviceId: string, screenTimeData: any) {
  try {
    // Get device settings and limits
    const deviceDoc = await db.collection('childDevices').doc(deviceId).get();
    if (!deviceDoc.exists) return;
    
    const deviceData = deviceDoc.data();
    const parentId = deviceData?.parentId;
    
    if (!parentId) return;
    
    const totalScreenTime = screenTimeData.totalScreenTime || 0;
    const dailyLimit = deviceData?.dailyScreenTimeLimit || 4 * 60 * 60; // 4 hours default
    
    // Check if daily limit is exceeded
    if (totalScreenTime > dailyLimit) {
      const notificationData = {
        parentId: parentId,
        deviceId: deviceId,
        type: 'screen_time_limit_exceeded',
        title: 'Daily Screen Time Limit Exceeded',
        message: `Your child has exceeded the daily screen time limit of ${Math.round(dailyLimit / 3600)} hours.`,
        timestamp: admin.firestore.Timestamp.now(),
        isRead: false,
        data: {
          currentScreenTime: totalScreenTime,
          dailyLimit: dailyLimit
        }
      };
      
      await db.collection('notifications').add(notificationData);
      console.log(`🔔 Sent screen time limit notification for device ${deviceId}`);
    }
    
    // Check for excessive app usage
    const appUsages = screenTimeData.appUsages || [];
    for (const appUsage of appUsages) {
      const appLimit = deviceData?.appLimits?.[appUsage.bundleIdentifier];
      if (appLimit && appUsage.duration > appLimit * 3600) { // Convert hours to seconds
        const notificationData = {
          parentId: parentId,
          deviceId: deviceId,
          type: 'app_limit_exceeded',
          title: 'App Usage Limit Exceeded',
          message: `Your child has exceeded the time limit for ${appUsage.appName}.`,
          timestamp: admin.firestore.Timestamp.now(),
          isRead: false,
          data: {
            appName: appUsage.appName,
            currentUsage: appUsage.duration,
            appLimit: appLimit
          }
        };
        
        await db.collection('notifications').add(notificationData);
        console.log(`🔔 Sent app limit notification for ${appUsage.appName}`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error checking notifications:', error);
  }
}

// Helper function to update screen time aggregations
async function updateScreenTimeAggregations(deviceId: string, screenTimeData: any) {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const aggregationRef = db.collection('screenTimeAggregations').doc(`${deviceId}_${today.toISOString().split('T')[0]}`);
    
    const currentData = await aggregationRef.get();
    let aggregation: any = currentData.exists ? currentData.data() : {
      deviceId: deviceId,
      date: today,
      totalScreenTime: 0,
      appUsageTotals: {},
      hourlyBreakdown: {},
      lastUpdated: admin.firestore.Timestamp.now()
    };
    
    // Ensure aggregation object exists
    if (!aggregation) {
      aggregation = {
        deviceId: deviceId,
        date: today,
        totalScreenTime: 0,
        appUsageTotals: {},
        hourlyBreakdown: {},
        lastUpdated: admin.firestore.Timestamp.now()
      };
    }
    
    // Update totals
    aggregation.totalScreenTime = (aggregation.totalScreenTime || 0) + (screenTimeData.totalScreenTime || 0);
    aggregation.lastUpdated = admin.firestore.Timestamp.now();
    
    // Update app usage totals
    const appUsages = screenTimeData.appUsages || [];
    for (const appUsage of appUsages) {
      const appName = appUsage.appName;
      if (!aggregation.appUsageTotals) {
        aggregation.appUsageTotals = {};
      }
      aggregation.appUsageTotals[appName] = (aggregation.appUsageTotals[appName] || 0) + appUsage.duration;
    }
    
    // Update hourly breakdown
    const hourlyBreakdown = screenTimeData.hourlyBreakdown || {};
    for (const [hour, duration] of Object.entries(hourlyBreakdown)) {
      const hourKey = hour.toString();
      if (!aggregation.hourlyBreakdown) {
        aggregation.hourlyBreakdown = {};
      }
      const durationValue = typeof duration === 'number' ? duration : 0;
      aggregation.hourlyBreakdown[hourKey] = (aggregation.hourlyBreakdown[hourKey] || 0) + durationValue;
    }
    
    await aggregationRef.set(aggregation);
    console.log(`📊 Updated aggregations for device ${deviceId}`);
    
  } catch (error) {
    console.error('❌ Error updating aggregations:', error);
  }
}

// Helper function to aggregate device screen time
async function aggregateDeviceScreenTime(deviceId: string, documents: any[], date: Date) {
  try {
    let totalScreenTime = 0;
    const appUsageTotals: { [appName: string]: number } = {};
    const hourlyBreakdown: { [hour: string]: number } = {};
    
    // Aggregate data from all documents
    for (const doc of documents) {
      totalScreenTime += doc.totalScreenTime || 0;
      
      // Aggregate app usage
      const appUsages = doc.appUsages || [];
      for (const appUsage of appUsages) {
        const appName = appUsage.appName;
        appUsageTotals[appName] = (appUsageTotals[appName] || 0) + appUsage.duration;
      }
      
      // Aggregate hourly breakdown
      const hourly = doc.hourlyBreakdown || {};
      for (const [hour, duration] of Object.entries(hourly)) {
        const hourKey = hour.toString();
        const durationValue = typeof duration === 'number' ? duration : 0;
        hourlyBreakdown[hourKey] = (hourlyBreakdown[hourKey] || 0) + durationValue;
      }
    }
    
    // Save daily aggregation
    const aggregationData = {
      deviceId: deviceId,
      date: date,
      totalScreenTime: totalScreenTime,
      appUsageTotals: appUsageTotals,
      hourlyBreakdown: hourlyBreakdown,
      documentCount: documents.length,
      aggregatedAt: admin.firestore.Timestamp.now()
    };
    
    const dateKey = date.toISOString().split('T')[0];
    await db.collection('screenTimeAggregations').doc(`${deviceId}_${dateKey}`).set(aggregationData);
    
    console.log(`📊 Aggregated data for device ${deviceId} on ${dateKey}`);
    
  } catch (error) {
    console.error(`❌ Error aggregating data for device ${deviceId}:`, error);
  }
} 