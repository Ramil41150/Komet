

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'package:gwid/screens/settings/customization_screen.dart';
import 'package:gwid/screens/settings/animations_screen.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  final bool isModal;
  
  const AppearanceSettingsScreen({super.key, this.isModal = false});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = Theme.of(context).colorScheme;

    if (isModal) {
      return buildModalContent(context);
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Внешний вид")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("Кастомизация", colors),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text("Настройки тем"),
                  subtitle: const Text("Тема, обои и другие настройки"),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => CustomizationScreen(),
                      ),
                    );
                  },
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.animation),
                  title: const Text("Настройки анимаций"),
                  subtitle: const Text("Анимации сообщений и переходов"),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AnimationsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _OutlinedSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("Производительность", colors),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.speed_outlined),
                  title: const Text("Оптимизация чатов"),
                  subtitle: const Text("Улучшить производительность в чатах"),
                  value: theme.optimizeChats,
                  onChanged: (value) => theme.setOptimizeChats(value),
                ),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.flash_on_outlined),
                  title: const Text("Ультра оптимизация"),
                  subtitle: const Text("Максимальная производительность"),
                  value: theme.ultraOptimizeChats,
                  onChanged: (value) => theme.setUltraOptimizeChats(value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildModalContent(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OutlinedSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Кастомизация", colors),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text("Настройки тем"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CustomizationScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.animation_outlined),
                title: const Text("Анимации"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AnimationsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _OutlinedSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Производительность", colors),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.speed_outlined),
                title: const Text("Ультра-оптимизация чатов"),
                subtitle: const Text("Максимальная производительность"),
                value: theme.ultraOptimizeChats,
                onChanged: (value) => theme.setUltraOptimizeChats(value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModalSettings(BuildContext context, ThemeProvider theme, ColorScheme colors) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [

          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withOpacity(0.3),
            ),
          ),
          

          Center(
            child: Container(
              width: 400,
              height: 600,
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Назад',
                        ),
                        const Expanded(
                          child: Text(
                            "Внешний вид",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: 'Закрыть',
                        ),
                      ],
                    ),
                  ),
                  

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _OutlinedSection(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle("Кастомизация", colors),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.palette_outlined),
                                title: const Text("Настройки тем"),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const CustomizationScreen(),
                                    ),
                                  );
                                },
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.animation_outlined),
                                title: const Text("Анимации"),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => const AnimationsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _OutlinedSection(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionTitle("Производительность", colors),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                secondary: const Icon(Icons.speed_outlined),
                                title: const Text("Ультра-оптимизация чатов"),
                                subtitle: const Text("Максимальная производительность"),
                                value: theme.ultraOptimizeChats,
                                onChanged: (value) => theme.setUltraOptimizeChats(value),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _OutlinedSection extends StatelessWidget {
  final Widget child;
  const _OutlinedSection({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
