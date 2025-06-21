// Reexport the native module. On web, it will be resolved to ReactNativePcmPlayerModule.web.ts
// and on native platforms to ReactNativePcmPlayerModule.ts
export { default } from './ReactNativePcmPlayerModule';
export { default as ReactNativePcmPlayerView } from './ReactNativePcmPlayerView';
export * from  './ReactNativePcmPlayer.types';
