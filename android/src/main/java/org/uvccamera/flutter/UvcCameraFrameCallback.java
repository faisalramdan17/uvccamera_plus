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

        // Check if we're already on the main thread
        if (Looper.myLooper() == Looper.getMainLooper()) {
            // Already on main thread, process directly
            processFrame(frame, eventSink);
        } else {
            // Post to main thread
            new Handler(Looper.getMainLooper()).post(() -> {
                processFrame(frame, eventSink);
            });
        }
    }

    private void processFrame(ByteBuffer frame, io.flutter.plugin.common.EventChannel.EventSink eventSink) {
        try {
            // Get frame data
            final byte[] frameData = new byte[frame.remaining()];
            frame.get(frameData);
            frame.rewind(); // Reset buffer position for potential reuse

            // Create frame event data
            final Map<String, Object> frameEvent = new HashMap<>();
            frameEvent.put("imageData", frameData);
            frameEvent.put("width", width); // Use dynamic width
            frameEvent.put("height", height); // Use dynamic height
            frameEvent.put("timestamp", System.currentTimeMillis());
            frameEvent.put("format", pixelFormat); // Use dynamically determined format

            // Send frame event to Flutter (should be on main thread now)
            if (eventSink != null) {
                eventSink.success(frameEvent);
            }

        } catch (Exception e) {
            android.util.Log.e(TAG, "Error processing frame", e);
            if (eventSink != null) {
                eventSink.error("FRAME_PROCESSING_ERROR", "Error processing camera frame: " + e.getMessage(), null);
            }
        }
    }
}
