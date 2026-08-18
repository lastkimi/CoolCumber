import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUTPUT_DIR = "/Users/brucelieu/Desktop/MacThermFlow/AppStore_Screenshots"
os.makedirs(OUTPUT_DIR, exist_ok=True)

APP_IMG_PATH = "/Users/brucelieu/.gemini/antigravity/brain/b284e1ca-2a54-4936-b9a5-40e6acd827e5/coolcumber_app_screenshot_v2_1783509213536.jpg"
WIDGET_IMG_PATH = "/Users/brucelieu/.gemini/antigravity/brain/b284e1ca-2a54-4936-b9a5-40e6acd827e5/coolcumber_widget_screenshot_v2_1783509224085.jpg"

WIDTH, HEIGHT = 2880, 1800

# Try to find a nice system font on macOS
FONT_PATH_BOLD = "/System/Library/Fonts/SFPro-Bold.otf" if os.path.exists("/System/Library/Fonts/SFPro-Bold.otf") else "/System/Library/Fonts/PingFang.ttc"
FONT_PATH_REGULAR = "/System/Library/Fonts/SFPro-Regular.otf" if os.path.exists("/System/Library/Fonts/SFPro-Regular.otf") else "/System/Library/Fonts/PingFang.ttc"

def create_gradient_bg(color_top, color_bottom):
    base = Image.new('RGB', (WIDTH, HEIGHT), color_top)
    top_r, top_g, top_b = color_top
    bot_r, bot_g, bot_b = color_bottom
    
    draw = ImageDraw.Draw(base)
    for y in range(HEIGHT):
        ratio = y / float(HEIGHT)
        r = int(top_r * (1 - ratio) + bot_r * ratio)
        g = int(top_g * (1 - ratio) + bot_g * ratio)
        b = int(top_b * (1 - ratio) + bot_b * ratio)
        draw.line([(0, y), (WIDTH, y)], fill=(r, g, b))
    return base

def draw_header_text(img, title, subtitle):
    draw = ImageDraw.Draw(img)
    try:
        font_title = ImageFont.truetype(FONT_PATH_BOLD, 78)
        font_sub = ImageFont.truetype(FONT_PATH_REGULAR, 40)
    except Exception:
        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()
    
    # Title
    t_bbox = draw.textbbox((0, 0), title, font=font_title)
    t_w = t_bbox[2] - t_bbox[0]
    draw.text(((WIDTH - t_w) / 2, 140), title, fill=(255, 255, 255), font=font_title)
    
    # Subtitle
    s_bbox = draw.textbbox((0, 0), subtitle, font=font_sub)
    s_w = s_bbox[2] - s_bbox[0]
    draw.text(((WIDTH - s_w) / 2, 240), subtitle, fill=(160, 175, 200), font=font_sub)

def rounded_corner_mask(size, radius):
    mask = Image.new('L', size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), size], radius, fill=255)
    return mask

def make_screenshot_1():
    print("Generating Screenshot 1: Overview Dashboard...")
    bg = create_gradient_bg((15, 23, 42), (8, 12, 24))
    draw_header_text(bg, "全维度硬件遥测与性能看板", "高频精确采集 CPU / GPU 温度、内存压力与芯片功耗")
    
    if os.path.exists(APP_IMG_PATH):
        src = Image.open(APP_IMG_PATH).convert('RGB')
        # Scale to fit nicely
        target_w = 2100
        target_h = int(src.height * (target_w / src.width))
        src = src.resize((target_w, target_h), Image.Resampling.LANCZOS)
        
        # Round corners
        mask = rounded_corner_mask((target_w, target_h), 28)
        
        # Shadow
        shadow = Image.new('RGBA', (target_w + 80, target_h + 80), (0, 0, 0, 0))
        s_draw = ImageDraw.Draw(shadow)
        s_draw.rounded_rectangle([(40, 40), (target_w + 40, target_h + 40)], 28, fill=(0, 0, 0, 160))
        shadow = shadow.filter(ImageFilter.GaussianBlur(35))
        
        pos_x = (WIDTH - target_w) // 2
        pos_y = 360
        bg.paste(shadow, (pos_x - 40, pos_y - 40), shadow)
        bg.paste(src, (pos_x, pos_y), mask)
        
    bg.save(os.path.join(OUTPUT_DIR, "1_dashboard_telemetry.png"), "PNG")

def make_screenshot_2():
    print("Generating Screenshot 2: Dynamic Island & SmartBar...")
    bg = create_gradient_bg((12, 18, 36), (6, 9, 20))
    draw_header_text(bg, "极简灵动岛 SmartBar 体验", "刘海吸顶常驻，鼠标悬停即刻展开微观状态")
    
    if os.path.exists(APP_IMG_PATH):
        src = Image.open(APP_IMG_PATH).convert('RGB')
        target_w = 2100
        target_h = int(src.height * (target_w / src.width))
        src = src.resize((target_w, target_h), Image.Resampling.LANCZOS)
        mask = rounded_corner_mask((target_w, target_h), 28)
        
        pos_x = (WIDTH - target_w) // 2
        pos_y = 360
        bg.paste(src, (pos_x, pos_y), mask)
        
    bg.save(os.path.join(OUTPUT_DIR, "2_dynamic_island.png"), "PNG")

def make_screenshot_3():
    print("Generating Screenshot 3: Desktop Widgets & Widgets...")
    bg = create_gradient_bg((18, 26, 48), (9, 14, 28))
    draw_header_text(bg, "macOS Sonoma & Sequoia 原生小组件", "桌面交互与菜单栏常驻态无缝联动")
    
    if os.path.exists(WIDGET_IMG_PATH):
        src = Image.open(WIDGET_IMG_PATH).convert('RGB')
        target_w = 2100
        target_h = int(src.height * (target_w / src.width))
        src = src.resize((target_w, target_h), Image.Resampling.LANCZOS)
        mask = rounded_corner_mask((target_w, target_h), 28)
        
        pos_x = (WIDTH - target_w) // 2
        pos_y = 360
        bg.paste(src, (pos_x, pos_y), mask)
        
    bg.save(os.path.join(OUTPUT_DIR, "3_widgets.png"), "PNG")

if __name__ == "__main__":
    make_screenshot_1()
    make_screenshot_2()
    make_screenshot_3()
    print("All screenshots generated in:", OUTPUT_DIR)
