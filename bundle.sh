#!/bin/bash
# Bundle the Hackathon prototype into a single self-contained HTML file
# Usage: bash bundle.sh

cd "$(dirname "$0")"

OUTPUT="index-bundled.html"
INPUT="index.html"

echo "Bundling $INPUT → $OUTPUT ..."

# Step 1: Read the HTML
cp "$INPUT" "$OUTPUT"

# Step 2: Inline the 3 CSS files
for cssfile in css/lpl-tokens.css css/lpl-components.css css/lpl-icons.css; do
  if [ -f "$cssfile" ]; then
    echo "  Inlining $cssfile ..."
  fi
done

# Step 3: Use Python for the heavy lifting (base64 encoding, CSS inlining, font embedding)
python3 - "$INPUT" "$OUTPUT" << 'PYEOF'
import sys, os, re, base64, mimetypes

input_file = sys.argv[1]
output_file = sys.argv[2]
base_dir = os.path.dirname(os.path.abspath(input_file)) or '.'

def file_to_data_uri(filepath):
    """Convert a file to a data URI."""
    if not os.path.exists(filepath):
        print(f"  WARNING: File not found: {filepath}")
        return None
    mime, _ = mimetypes.guess_type(filepath)
    if mime is None:
        ext = os.path.splitext(filepath)[1].lower()
        mime_map = {'.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.woff': 'font/woff',
                    '.ttf': 'font/ttf', '.otf': 'font/otf', '.png': 'image/png',
                    '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg'}
        mime = mime_map.get(ext, 'application/octet-stream')
    with open(filepath, 'rb') as f:
        data = base64.b64encode(f.read()).decode('ascii')
    return f"data:{mime};base64,{data}"

def inline_css_urls(css_content, css_dir):
    """Replace url(...) references in CSS with data URIs."""
    def replace_url(match):
        url = match.group(1).strip('\'"')
        if url.startswith('data:') or url.startswith('http'):
            return match.group(0)
        filepath = os.path.normpath(os.path.join(css_dir, url))
        data_uri = file_to_data_uri(filepath)
        if data_uri:
            print(f"    Inlined font/asset: {os.path.basename(filepath)}")
            return f"url({data_uri})"
        return match.group(0)
    return re.sub(r'url\(([^)]+)\)', replace_url, css_content)

# Read HTML
with open(os.path.join(base_dir, input_file), 'r', encoding='utf-8') as f:
    html = f.read()

# Inline CSS <link> tags
def replace_css_link(match):
    href = match.group(1)
    if href.startswith('http'):
        return match.group(0)
    css_path = os.path.normpath(os.path.join(base_dir, href))
    if not os.path.exists(css_path):
        print(f"  WARNING: CSS not found: {css_path}")
        return match.group(0)
    print(f"  Inlining CSS: {href}")
    css_dir = os.path.dirname(css_path)
    with open(css_path, 'r', encoding='utf-8') as f:
        css_content = f.read()
    # Inline any url() references within the CSS (fonts, images)
    css_content = inline_css_urls(css_content, css_dir)
    return f"<style>\n{css_content}\n</style>"

html = re.sub(r'<link\s+rel="stylesheet"\s+href="([^"]+)"[^>]*>', replace_css_link, html)

# Inline <img src="assets/..."> and <img src="...local...">
def replace_img_src(match):
    full_tag = match.group(0)
    src = match.group(1)
    if src.startswith('data:') or src.startswith('http'):
        return full_tag
    filepath = os.path.normpath(os.path.join(base_dir, src))
    data_uri = file_to_data_uri(filepath)
    if data_uri:
        print(f"  Inlined image: {src}")
        return full_tag.replace(src, data_uri)
    return full_tag

html = re.sub(r'<img\s[^>]*src="([^"]+)"[^>]*>', replace_img_src, html)

# Inline background-image url() in inline styles that reference local files
def replace_inline_bg(match):
    full = match.group(0)
    url = match.group(1)
    if url.startswith('data:') or url.startswith('http'):
        return full
    filepath = os.path.normpath(os.path.join(base_dir, url))
    data_uri = file_to_data_uri(filepath)
    if data_uri:
        print(f"  Inlined bg image: {url}")
        return full.replace(url, data_uri)
    return full

html = re.sub(r'url\([\'"]?([^)\'"]+)[\'"]?\)', replace_inline_bg, html)

# Inline JS references to local image paths (e.g., iconUrl: 'assets/...')
def replace_js_asset(match):
    quote = match.group(1)
    path = match.group(2)
    if path.startswith('data:') or path.startswith('http'):
        return match.group(0)
    filepath = os.path.normpath(os.path.join(base_dir, path))
    data_uri = file_to_data_uri(filepath)
    if data_uri:
        print(f"  Inlined JS asset ref: {path}")
        return f"{quote}{data_uri}{quote}"
    return match.group(0)

html = re.sub(r"(['\"])(assets/[^'\"]+)(['\"])", replace_js_asset, html)

# Write output
with open(os.path.join(base_dir, output_file), 'w', encoding='utf-8') as f:
    f.write(html)

print(f"\nDone! Output: {output_file}")
PYEOF

# Get file size
SIZE=$(du -h "$OUTPUT" | cut -f1)
echo ""
echo "✅ Bundled file: $OUTPUT ($SIZE)"
echo "   Share this single file — anyone can open it in a browser."
