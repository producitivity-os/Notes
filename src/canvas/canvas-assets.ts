import type { EndlessCanvasOptions } from "@productivity-os/canvas"

function pickMediaFile(
  accept: string,
  video = false,
): Promise<{
  dataUrl?: string
  src?: string
  name: string
  width: number
  height: number
} | null> {
  return new Promise((resolve) => {
    const input = document.createElement("input")
    input.type = "file"
    input.accept = accept
    input.onchange = () => {
      const file = input.files?.[0]
      if (!file) return resolve(null)
      const reader = new FileReader()
      reader.onload = () => {
        const source = String(reader.result)
        const media = document.createElement(video ? "video" : "img")
        media.onloadedmetadata = media.onload = () =>
          resolve({
            ...(video ? { src: source } : { dataUrl: source }),
            name: file.name,
            width: video
              ? (media as HTMLVideoElement).videoWidth
              : (media as HTMLImageElement).naturalWidth,
            height: video
              ? (media as HTMLVideoElement).videoHeight
              : (media as HTMLImageElement).naturalHeight,
          })
        media.onerror = () => resolve(null)
        media.src = source
      }
      reader.readAsDataURL(file)
    }
    input.click()
  })
}

export function createNotesCanvasAssets(): NonNullable<EndlessCanvasOptions["assets"]> {
  return {
    pickImage: async () => {
      const picked = await pickMediaFile("image/*")
      return picked?.dataUrl
        ? {
            dataUrl: picked.dataUrl,
            name: picked.name,
            width: picked.width,
            height: picked.height,
          }
        : null
    },
    pickVideo: async () => {
      const picked = await pickMediaFile("video/*", true)
      return picked?.src
        ? {
            src: picked.src,
            name: picked.name,
            width: picked.width,
            height: picked.height,
          }
        : null
    },
  }
}
