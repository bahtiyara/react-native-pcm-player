import { registerWebModule, NativeModule } from 'expo';

import { ReactNativePcmPlayerModuleEvents } from './ReactNativePcmPlayer.types';

class ReactNativePcmPlayerModule extends NativeModule<ReactNativePcmPlayerModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ReactNativePcmPlayerModule, 'ReactNativePcmPlayerModule');
