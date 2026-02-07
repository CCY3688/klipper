import 'package:flutter/material.dart';

class FluiddSidebar extends StatelessWidget {
  const FluiddSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      color: const Color(0xFF212529), // Dark background for sidebar
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Icon(Icons.print, color: Colors.blue, size: 32), // Logo placeholder
          const SizedBox(height: 32),
          _SideItem(icon: Icons.dashboard, isActive: true, onTap: () {}),
          _SideItem(icon: Icons.tv, onTap: () {}), // Console
          _SideItem(icon: Icons.history, onTap: () {}),
          const Spacer(),
          _SideItem(icon: Icons.settings, onTap: () {}),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _SideItem({required this.icon, this.isActive = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: isActive 
            ? const Border(left: BorderSide(color: Colors.blue, width: 3)) 
            : null,
          color: isActive ? Colors.white10 : null,
        ),
        child: Icon(
          icon, 
          color: isActive ? Colors.blue : Colors.grey,
        ),
      ),
    );
  }
}
