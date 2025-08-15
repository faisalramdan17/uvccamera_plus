package org.uvccamera.flutter;

import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Looper;

import com.serenegiant.usb.IFrameCallback;

import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;

/**
 * Frame callback for real-time image streaming from UVC camera
 * Enhanced for Android 14 compatibility with memory management and throttling
 */
/* package-private */ class UvcCameraFrameCallback implements IFrameCallback {

    /**
     * Log tag
     */
    private static final String TAG = UvcCameraFrameCallback.class.getCanonicalName();

    /**
     * Frame event stream handler
     */
    private final UvcCameraFrameEventStreamHandler frameEventStreamHandler;

    /**
     * Frame width
     */
    private final int width;

    /**
     * Frame height
     */
    private final int height;

    /**
     * Pixel format string
     */
    private final String pixelFormat;

    /**
     * Frame throttling for Android 14 compatibility
     */
    private long lastFrameProcessed = 0;
    private static final long FRAME_INTERVAL_MS = 100; // Max 10 FPS

    /**
     * Processing flag to prevent overlapping
     */
    private volatile boolean isProcessing = false;

    /**
     * Constructor
     *
     * @param frameEventStreamHandler Frame event stream handler
     * @param width Frame width
     * @param height Frame height
     * @param pixelFormat Pixel format string
     */
    public UvcCameraFrameCallback(UvcCameraFrameEventStreamHandler frameEventStreamHandler, int width, int height, String pixelFormat) {
        this.frameEventStreamHandler = frameEventStreamHandler;
        this.width = width;
        this.height = height;
        this.pixelFormat = pixelFormat;
    }

    @Override
    public void onFrame(ByteBuffer frame) {
        if (frameEventStreamHandler == null) {
            return;
        }

        final var eventSink = frameEventStreamHandler.getEventSink();
        if (eventSink == null) {
            return;
        }

        // Frame throttling for Android 14 compatibility
        long currentTime = System.currentTimeMillis();
        if (currentTime - lastFrameProcessed < FRAME_INTERVAL_MS) {
            return; // Skip this frame
        }

        // Prevent overlapping processing
        if (isProcessing) {
            return;
        }

        lastFrameProcessed = currentTime;

        // Check if we're already on the main thread
        if (Looper.myLooper() == Looper.getMainLooper()) {
            // Already on main thread, process directly
            processFrame(frame, eventSink);
        } else {
            // Post to main thread with better error handling
            try {
                new Handler(Looper.getMainLooper()).post(() -> {
                    processFrame(frame, eventSink);
                });
            } catch (Exception e) {
                android.util.Log.e(TAG, "Error posting frame to main thread", e);
            }
        }
    }

    private void processFrame(ByteBuffer frame, io.flutter.plugin.common.EventChannel.EventSink eventSink) {
        // Set processing flag
        isProcessing = true;
        
        try {
            // Validate frame buffer
            if (frame == null || !frame.hasRemaining()) {
                android.util.Log.w(TAG, "Invalid frame buffer received");
                return;
            }

            int frameSize = frame.remaining();
            // Safety check for reasonable frame size (max 10MB)
            if (frameSize <= 0 || frameSize > 10 * 1024 * 1024) {
                android.util.Log.w(TAG, "Frame size out of bounds: " + frameSize);
                return;
            }

            // Get frame data with memory management
            final byte[] frameData = new byte[frameSize];
            frame.get(frameData);
            frame.rewind(); // Reset buffer position for potential reuse

            // Create frame event data
            final Map<String, Object> frameEvent = new HashMap<>();
            frameEvent.put("imageData", frameData);
            frameEvent.put("width", width);
            frameEvent.put("height", height);
            frameEvent.put("timestamp", System.currentTimeMillis());
            frameEvent.put("format", pixelFormat);

            // Send frame event to Flutter with null check
            if (eventSink != null) {
                try {
                    eventSink.success(frameEvent);
                } catch (Exception e) {
                    android.util.Log.e(TAG, "Error sending frame to Flutter", e);
                }
            }

        } catch (OutOfMemoryError e) {
            android.util.Log.e(TAG, "Out of memory processing frame", e);
            // Force garbage collection
            System.gc();
        } catch (Exception e) {
            android.util.Log.e(TAG, "Error processing frame", e);
            if (eventSink != null) {
                try {
                    eventSink.error("FRAME_PROCESSING_ERROR", "Error processing camera frame: " + e.getMessage(), null);
                } catch (Exception sendError) {
                    android.util.Log.e(TAG, "Error sending error to Flutter", sendError);
                }
            }
        } finally {
            // Always reset processing flag
            isProcessing = false;
        }
    }
}
