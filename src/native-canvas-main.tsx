import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import "@productivity-os/shared-ui/globals.css"
import { SharedUiProvider } from "@productivity-os/shared-ui/components/shared-ui-provider"
import { NativeCanvasApp } from "./native-canvas/NativeCanvasApp"

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <SharedUiProvider applicationBackgroundMenu="none">
      <NativeCanvasApp />
    </SharedUiProvider>
  </StrictMode>,
)
