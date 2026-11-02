/// แถบนำทางด้านล่างที่รับ index ปัจจุบันและ callback จากหน้าหลัก.
import 'package:flutter/material.dart';

/// รายการเมนูถูกกำหนดเป็นข้อมูลคู่ icon/label แล้ววาดตาม currentIndex.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_rounded, Icons.home_outlined, 'หน้าหลัก'),
    (Icons.groups_rounded, Icons.groups_2_outlined, 'ค้นหาตี้'),
    (Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'แชต'),
    (Icons.person_rounded, Icons.person_outline_rounded, 'โปรไฟล์'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF214131F),
        border: Border(top: BorderSide(color: Color(0xFF292735))),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, -5))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: List.generate(_items.length, (index) {
              final selected = index == currentIndex;
              final item = _items[index];
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  borderRadius: BorderRadius.circular(16),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF332A4E) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(selected ? item.$1 : item.$2,
                              size: 20,
                              color: selected ? const Color(0xFFB69EFF) : const Color(0xFF858195)),
                          const SizedBox(height: 2),
                          Text(item.$3,
                              style: TextStyle(
                                fontSize: 9,
                                height: 1,
                                color: selected ? const Color(0xFFB69EFF) : const Color(0xFF858195),
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
