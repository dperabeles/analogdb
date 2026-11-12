/// Frame sizes of a 120 camera (ANA-135). Informative: nothing depends on
/// them, and any other format has none (the database drops it too).
export const CAMERA_FRAME_SIZES = ["6x4.5", "6x6", "6x7", "6x8", "6x9", "6x12", "6x17"] as const;

export type CameraFrameSize = (typeof CAMERA_FRAME_SIZES)[number];

export function cameraFrameSize(format: string | null, value: string | null): CameraFrameSize | null {
  if (format !== "120" || !value) return null;
  return (CAMERA_FRAME_SIZES as readonly string[]).includes(value) ? (value as CameraFrameSize) : null;
}
