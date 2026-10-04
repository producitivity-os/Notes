import type { EndlessCanvasState } from "@productivity-os/canvas"

export const NATIVE_BRIDGE_VERSION = 1

export type NativePage = {
  pageID: string
  revision: number
  width: number
  height: number
  canvas: EndlessCanvasState
}

export type NativeEnvelope = {
  version: number
  type: string
  body: Record<string, unknown>
}

type Receiver = (message: NativeEnvelope) => void

export type NativeImportedAsset = {
  requestID: string
  hash: string
  filename: string
  mediaType: string
  url: string
  width: number
  height: number
}

type AssetWaiter = {
  resolve: (asset: NativeImportedAsset | null) => void
  reject: (error: Error) => void
}

type NativeRequestWaiter = {
  resolve: (value: unknown) => void
  reject: (error: Error) => void
}

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        notesBridge?: { postMessage(message: NativeEnvelope): void }
      }
    }
    notesNative?: { receive(message: NativeEnvelope): void }
  }
}

const receivers = new Set<Receiver>()
const assetWaiters = new Map<string, AssetWaiter>()
const nativeRequestWaiters = new Map<string, NativeRequestWaiter>()

function requestID() {
  return globalThis.crypto?.randomUUID?.()
    ?? `native-${Date.now()}-${Math.random().toString(36).slice(2)}`
}

window.notesNative = {
  receive(message) {
    if (message.version !== NATIVE_BRIDGE_VERSION) return
    if (message.type === "assetImported") {
      const asset = message.body as unknown as NativeImportedAsset
      const waiter = assetWaiters.get(asset.requestID)
      if (waiter) {
        assetWaiters.delete(asset.requestID)
        waiter.resolve(asset)
      }
    } else if (message.type === "assetImportCancelled" || message.type === "assetImportFailed") {
      const requestID = message.body.requestID
      if (typeof requestID === "string") {
        const waiter = assetWaiters.get(requestID)
        if (waiter) {
          assetWaiters.delete(requestID)
          if (message.type === "assetImportFailed") {
            waiter.reject(new Error(String(message.body.message ?? "The asset could not be imported.")))
          } else {
            waiter.resolve(null)
          }
        }
      }
    } else if (message.type === "nativeRequestResolved" || message.type === "nativeRequestRejected") {
      const requestID = message.body.requestID
      if (typeof requestID === "string") {
        const waiter = nativeRequestWaiters.get(requestID)
        if (waiter) {
          nativeRequestWaiters.delete(requestID)
          if (message.type === "nativeRequestRejected") {
            waiter.reject(new Error(String(message.body.message ?? "The native request failed.")))
          } else {
            waiter.resolve(message.body.value)
          }
        }
      }
    }
    receivers.forEach((receiver) => receiver(message))
  },
}

export function subscribeNativeBridge(receiver: Receiver) {
  receivers.add(receiver)
  return () => {
    receivers.delete(receiver)
  }
}

export function postNative(type: string, body: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers?.notesBridge?.postMessage({
    version: NATIVE_BRIDGE_VERSION,
    type,
    body,
  })
}

export function requestNativeAsset(kind: "image" | "video") {
  return requestAsset("importAsset", { kind })
}

export function uploadNativeImage(dataURL: string, name: string) {
  return requestAsset("importAssetData", { dataURL, name, kind: "image" })
}

export function requestNative<T>(type: string, body: Record<string, unknown> = {}) {
  const nativeRequestID = requestID()
  return new Promise<T>((resolve, reject) => {
    nativeRequestWaiters.set(nativeRequestID, {
      resolve: (value) => resolve(value as T),
      reject,
    })
    postNative(type, { ...body, requestID: nativeRequestID })
  })
}

function requestAsset(type: string, body: Record<string, unknown>) {
  const nativeRequestID = requestID()
  return new Promise<NativeImportedAsset | null>((resolve, reject) => {
    assetWaiters.set(nativeRequestID, { resolve, reject })
    postNative(type, { ...body, requestID: nativeRequestID })
  })
}
