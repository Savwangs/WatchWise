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
    
    console.log(`📱 Updating device activity for user: ${userId}`);
    
    // Update user's last activity
    await db.collection('users').doc(userId).update({
      lastActiveAt: admin.firestore.Timestamp.now(),
      deviceInfo: deviceInfo || null,
      lastActivityType: activityType || 'app_opened'
    });
    
    // Update device status in parent-child relationships
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
    
    return { success: true };
  } catch (error) {
    console.error('❌ Error updating device activity:', error);
    throw new functions.https.HttpsError('internal', 'Failed to update device activity');
  }
});

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