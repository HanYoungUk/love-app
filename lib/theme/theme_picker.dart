import 'package:flutter/material.dart';
import 'app_theme.dart';

/// 테마 선택 바텀시트. 홈 헤더의 🎨 버튼에서 연다.
/// 고르면 즉시 저장되고(기기 로컬) 앱 전체가 새 색으로 다시 그려진다.
Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    // 기본 바텀시트는 화면 높이의 9/16까지만 커진다. 색상 6칸 + 닫기 버튼이
    // 그보다 높아서 아래가 잘렸다.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: ValueListenableBuilder<AppPalette>(
          valueListenable: AppTheme.current,
          builder: (context, selected, _) {
            return ConstrainedBox(
              // 화면이 아주 낮으면(가로 모드 등) 시트 안에서 스크롤되게 한다
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '테마 색상',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '이 기기에만 적용돼요',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.95,
                        children: [
                          for (final p in AppTheme.palettes)
                            _PaletteTile(
                              palette: p,
                              selected: p.id == selected.id,
                              onTap: () => AppTheme.set(p),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('닫기',
                              style: TextStyle(color: AppTheme.primary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

class _PaletteTile extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: palette.gradient,
            stops: palette.gradientStops,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            // 밝은 테마 타일은 흰 시트에 묻히니 테두리를 준다
            color: selected
                ? Colors.black87
                : (palette.isLight
                    ? const Color(0xFFDDDDDD)
                    : Colors.transparent),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(palette.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 6),
                  Text(
                    palette.label,
                    // 밝은 테마 타일은 글씨가 흰색이면 안 보인다
                    style: TextStyle(
                      color: palette.onGradient,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.check_circle,
                    color: palette.onGradient, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
