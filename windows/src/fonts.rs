use std::sync::Arc;

use eframe::egui::{self, FontData, FontDefinitions, FontFamily};

pub fn install(ctx: &egui::Context) {
    let mut fonts = FontDefinitions::default();
    let name = "Noto Sans CJK";
    fonts.font_data.insert(
        name.into(),
        Arc::new(FontData::from_static(include_bytes!(
            "../fonts/NotoSansCJKkr-Regular.otf"
        ))),
    );
    // Keep the existing Latin text, with CJK available on every Windows locale.
    for family in [FontFamily::Proportional, FontFamily::Monospace] {
        fonts.families.entry(family).or_default().push(name.into());
    }
    ctx.set_fonts(fonts);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_latin_korean_chinese_and_japanese_names() {
        let ctx = egui::Context::default();
        install(&ctx);
        let _ = ctx.run(Default::default(), |ctx| {
            ctx.fonts(|fonts| {
                for family in [FontFamily::Proportional, FontFamily::Monospace] {
                    let font = egui::FontId::new(14.0, family);
                    assert!(fonts.has_glyphs(&font, "Player 한글 中文 漢字 日本語"));
                }
            });
        });
    }
}
