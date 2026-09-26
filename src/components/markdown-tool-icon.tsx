import markdownIconUrl from "@/assets/icons/svg/markdown-svgrepo-com.svg";

export function MarkdownToolIcon() {
  return (
    <span aria-hidden="true" className="notes-markdown-tool-icon">
      <span
        className="notes-markdown-tool-icon__mask"
        style={{
          WebkitMaskImage: `url("${markdownIconUrl}")`,
          maskImage: `url("${markdownIconUrl}")`,
        }}
      />
      <img
        alt=""
        className="notes-markdown-tool-icon__fallback"
        src={markdownIconUrl}
      />
    </span>
  );
}
