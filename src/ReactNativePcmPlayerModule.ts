import { NativeModule, requireNativeModule } from "expo";
import { ReactNativePcmPlayerModuleEvents } from "./ReactNativePcmPlayer.types";

declare class ReactNativePcmPlayerModule extends NativeModule<ReactNativePcmPlayerModuleEvents> {
  enqueuePcm(base64Data: string): Promise<void>;
  stopCurrentPcm(): void;
  markAsEnded(): void;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ReactNativePcmPlayerModule>(
  "ReactNativePcmPlayer"
);
