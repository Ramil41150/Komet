import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:gwid/utils/theme_provider.dart';
import 'dart:io';
import 'dart:ui';
import 'package:gwid/models/message.dart';
import 'package:gwid/widgets/chat_message_bubble.dart';
import 'package:flutter/scheduler.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:video_player/video_player.dart';

void _showColorPicker(
  BuildContext context, {
  required Color initialColor,
  required ValueChanged<Color> onColorChanged,
}) {
  Color pickedColor = initialColor;

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Выберите цвет"),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return ColorPicker(
              pickerColor: pickedColor,
              onColorChanged: (color) {
                setState(() => pickedColor = color);
              },
              enableAlpha: false,
              pickerAreaHeightPercent: 0.8,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Отмена'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: const Text('Готово'),
          onPressed: () {
            onColorChanged(pickedColor);
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
  );
}

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key});

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = Theme.of(context).colorScheme;
    final bool isSystemTheme = theme.appTheme == AppTheme.system;
    final bool isCurrentlyDark =
        Theme.of(context).brightness == Brightness.dark;

    if (isSystemTheme) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final systemAccentColor = Theme.of(context).colorScheme.primary;
          theme.updateBubbleColorsForSystemTheme(systemAccentColor);
        }
      });
    }

    final Color? myBubbleColorToShow = isCurrentlyDark
        ? theme.myBubbleColorDark
        : theme.myBubbleColorLight;
    final Color? theirBubbleColorToShow = isCurrentlyDark
        ? theme.theirBubbleColorDark
        : theme.theirBubbleColorLight;

    final Function(Color?) myBubbleSetter = isCurrentlyDark
        ? theme.setMyBubbleColorDark
        : theme.setMyBubbleColorLight;
    final Function(Color?) theirBubbleSetter = isCurrentlyDark
        ? theme.setTheirBubbleColorDark
        : theme.setTheirBubbleColorLight;

    final Color myBubbleFallback = isCurrentlyDark
        ? const Color(0xFF2b5278)
        : Colors.blue.shade100;
    final Color theirBubbleFallback = isCurrentlyDark
        ? const Color(0xFF182533)
        : Colors.grey.shade200;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Кастомизация"),
        surfaceTintColor: Colors.transparent,
        backgroundColor: colors.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        children: [
          const _MessagePreviewSection(),
          const SizedBox(height: 24),
          const _ThemeManagementSection(),
          const SizedBox(height: 24),
          _ModernSection(
            title: "Тема приложения",
            children: [
              AppThemeSelector(
                selectedTheme: theme.appTheme,
                onChanged: (appTheme) => theme.setTheme(appTheme),
              ),
              const SizedBox(height: 16),
              IgnorePointer(
                ignoring: isSystemTheme,
                child: Opacity(
                  opacity: isSystemTheme ? 0.5 : 1.0,
                  child: _ColorPickerTile(
                    title: "Акцентный цвет",
                    subtitle: isSystemTheme
                        ? "Используются цвета системы (Material You)"
                        : "Основной цвет интерфейса",
                    color: isSystemTheme ? colors.primary : theme.accentColor,
                    onColorChanged: (color) => theme.setAccentColor(color),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ModernSection(
            title: "Обои чата",
            children: [
              _CustomSettingTile(
                icon: Icons.wallpaper,
                title: "Использовать свои обои",
                child: Switch(
                  value: theme.useCustomChatWallpaper,
                  onChanged: (value) => theme.setUseCustomChatWallpaper(value),
                ),
              ),
              if (theme.useCustomChatWallpaper) ...[
                const Divider(height: 24),
                _CustomSettingTile(
                  icon: Icons.image,
                  title: "Тип обоев",
                  child: DropdownButton<ChatWallpaperType>(
                    value: theme.chatWallpaperType,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) {
                      if (value != null) theme.setChatWallpaperType(value);
                    },
                    items: ChatWallpaperType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName),
                      );
                    }).toList(),
                  ),
                ),
                if (theme.chatWallpaperType == ChatWallpaperType.solid ||
                    theme.chatWallpaperType == ChatWallpaperType.gradient) ...[
                  const SizedBox(height: 16),
                  _ColorPickerTile(
                    title: "Цвет 1",
                    subtitle: "Основной цвет фона",
                    color: theme.chatWallpaperColor1,
                    onColorChanged: (color) =>
                        theme.setChatWallpaperColor1(color),
                  ),
                ],
                if (theme.chatWallpaperType == ChatWallpaperType.gradient) ...[
                  const SizedBox(height: 16),
                  _ColorPickerTile(
                    title: "Цвет 2",
                    subtitle: "Дополнительный цвет для градиента",
                    color: theme.chatWallpaperColor2,
                    onColorChanged: (color) =>
                        theme.setChatWallpaperColor2(color),
                  ),
                ],
                if (theme.chatWallpaperType == ChatWallpaperType.image) ...[
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text("Выбрать изображение"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (image != null) {
                        theme.setChatWallpaperImagePath(image.path);
                      }
                    },
                  ),
                  if (theme.chatWallpaperImagePath?.isNotEmpty == true) ...[
                    _SliderTile(
                      icon: Icons.blur_on,
                      label: "Размытие",
                      value: theme.chatWallpaperImageBlur,
                      min: 0.0,
                      max: 10.0,
                      divisions: 20,
                      onChanged: (value) =>
                          theme.setChatWallpaperImageBlur(value),
                      displayValue: theme.chatWallpaperImageBlur
                          .toStringAsFixed(1),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        "Удалить изображение",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () => theme.setChatWallpaperImagePath(null),
                    ),
                  ],
                ],
                if (theme.chatWallpaperType == ChatWallpaperType.video) ...[
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.video_library_outlined),
                    title: const Text("Выбрать видео"),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {

                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.video,
                      );
                      if (result != null && result.files.single.path != null) {
                        theme.setChatWallpaperVideoPath(
                          result.files.single.path!,
                        );
                      }
                    },
                  ),
                  if (theme.chatWallpaperVideoPath?.isNotEmpty == true) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      title: const Text(
                        "Удалить видео",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                      onTap: () => theme.setChatWallpaperVideoPath(null),
                    ),
                  ],
                ],
              ],
            ],
          ),
          const SizedBox(height: 24),
          _ModernSection(
            title: "Сообщения",
            children: [
              _SliderTile(
                icon: Icons.text_fields,
                label: "Непрозрачность текста",
                value: theme.messageTextOpacity,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                onChanged: (value) => theme.setMessageTextOpacity(value),
                displayValue: "${(theme.messageTextOpacity * 100).round()}%",
              ),
              _SliderTile(
                icon: Icons.blur_circular,
                label: "Интенсивность тени",
                value: theme.messageShadowIntensity,
                min: 0.0,
                max: 0.5,
                divisions: 10,
                onChanged: (value) => theme.setMessageShadowIntensity(value),
                displayValue:
                    "${(theme.messageShadowIntensity * 100).round()}%",
              ),
              _SliderTile(
                icon: Icons.rounded_corner,
                label: "Скругление углов",
                value: theme.messageBorderRadius,
                min: 4.0,
                max: 50.0,
                divisions: 23,
                onChanged: (value) => theme.setMessageBorderRadius(value),
                displayValue: "${theme.messageBorderRadius.round()}px",
              ),
              const Divider(height: 24),
              _SliderTile(
                icon: Icons.menu,
                label: "Непрозрачность меню",
                value: theme.messageMenuOpacity,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                onChanged: (value) => theme.setMessageMenuOpacity(value),
                displayValue: "${(theme.messageMenuOpacity * 100).round()}%",
              ),
              _SliderTile(
                icon: Icons.blur_on,
                label: "Размытие меню",
                value: theme.messageMenuBlur,
                min: 0.0,
                max: 20.0,
                divisions: 20,
                onChanged: (value) => theme.setMessageMenuBlur(value),
                displayValue: theme.messageMenuBlur.toStringAsFixed(1),
              ),
              const Divider(height: 24),
              if (MediaQuery.of(context).size.height < 600)
                const SizedBox(height: 5),
              _SliderTile(
                icon: Icons.opacity,
                label: "Непрозрачность сообщений",
                value: 1.0 - theme.messageBubbleOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (value) =>
                    theme.setMessageBubbleOpacity(1.0 - value),
                displayValue:
                    "${((1.0 - theme.messageBubbleOpacity) * 100).round()}%",
              ),
              const SizedBox(height: 16),
              _CustomSettingTile(
                icon: Icons.format_color_fill,
                title: "Тип отображения",
                child: IgnorePointer(
                  ignoring: isSystemTheme,
                  child: Opacity(
                    opacity: isSystemTheme ? 0.5 : 1.0,
                    child: DropdownButton<MessageBubbleType>(
                      value: theme.messageBubbleType,
                      underline: const SizedBox.shrink(),
                      onChanged: (value) {
                        if (value != null) theme.setMessageBubbleType(value);
                      },
                      items: MessageBubbleType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.displayName),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _CustomSettingTile(
                icon: Icons.palette,
                title: "Цвет моих сообщений",
                child: IgnorePointer(
                  ignoring: isSystemTheme,
                  child: Opacity(
                    opacity: isSystemTheme ? 0.5 : 1.0,
                    child: GestureDetector(
                      onTap: () async {
                        final initial = myBubbleColorToShow ?? myBubbleFallback;
                        _showColorPicker(
                          context,
                          initialColor: initial,
                          onColorChanged: (color) => myBubbleSetter(color),
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: myBubbleColorToShow ?? myBubbleFallback,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _CustomSettingTile(
                icon: Icons.palette_outlined,
                title: "Цвет сообщений собеседника",
                child: IgnorePointer(
                  ignoring: isSystemTheme,
                  child: Opacity(
                    opacity: isSystemTheme ? 0.5 : 1.0,
                    child: GestureDetector(
                      onTap: () async {
                        final initial =
                            theirBubbleColorToShow ?? theirBubbleFallback;
                        _showColorPicker(
                          context,
                          initialColor: initial,
                          onColorChanged: (color) => theirBubbleSetter(color),
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theirBubbleColorToShow ?? theirBubbleFallback,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 24),
              _CustomSettingTile(
                icon: Icons.reply,
                title: "Автоцвет панели ответа",
                subtitle: "",
                child: Switch(
                  value: theme.useAutoReplyColor,
                  onChanged: (value) => theme.setUseAutoReplyColor(value),
                ),
              ),
              if (!theme.useAutoReplyColor) ...[
                const SizedBox(height: 16),
                _ColorPickerTile(
                  title: "Цвет панели ответа",
                  subtitle: "Фиксированный цвет",
                  color: theme.customReplyColor ?? Colors.blue,
                  onColorChanged: (color) => theme.setCustomReplyColor(color),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          _ModernSection(
            title: "Всплывающие окна",
            children: [
              _SliderTile(
                icon: Icons.opacity,
                label: "Прозрачность фона (профиль)",
                value: theme.profileDialogOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (value) => theme.setProfileDialogOpacity(value),
                displayValue: "${(theme.profileDialogOpacity * 100).round()}%",
              ),
              _SliderTile(
                icon: Icons.blur_on,
                label: "Размытие фона (профиль)",
                value: theme.profileDialogBlur,
                min: 0.0,
                max: 30.0,
                divisions: 30,
                onChanged: (value) => theme.setProfileDialogBlur(value),
                displayValue: theme.profileDialogBlur.toStringAsFixed(1),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ModernSection(
            title: "Режим рабочего стола",
            children: [
              _CustomSettingTile(
                icon: Icons.desktop_windows,
                title: "Режим с контактами слева",
                subtitle: "Контакты слева, чат справа",
                child: Switch(
                  value: theme.useDesktopLayout,
                  onChanged: (value) => theme.setUseDesktopLayout(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _ModernSection(
            title: "Панели чата",
            children: [
              _CustomSettingTile(
                icon: Icons.tune,
                title: "Эффект стекла для панелей",
                subtitle: "Размытие и прозрачность",
                child: Switch(
                  value: theme.useGlassPanels,
                  onChanged: (value) => theme.setUseGlassPanels(value),
                ),
              ),
              if (theme.useGlassPanels) ...[
                const Divider(height: 24, indent: 16, endIndent: 16),
                _SliderTile(
                  label: "Непрозрачность верхней панели",
                  value: theme.topBarOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  onChanged: (value) => theme.setTopBarOpacity(value),
                  displayValue: "${(theme.topBarOpacity * 100).round()}%",
                ),
                _SliderTile(
                  label: "Размытие верхней панели",
                  value: theme.topBarBlur,
                  min: 0.0,
                  max: 20.0,
                  divisions: 40,
                  onChanged: (value) => theme.setTopBarBlur(value),
                  displayValue: theme.topBarBlur.toStringAsFixed(1),
                ),
                const Divider(height: 24, indent: 16, endIndent: 16),
                _SliderTile(
                  label: "Непрозрачность нижней панели",
                  value: theme.bottomBarOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 18,
                  onChanged: (value) => theme.setBottomBarOpacity(value),
                  displayValue: "${(theme.bottomBarOpacity * 100).round()}%",
                ),
                _SliderTile(
                  label: "Размытие нижней панели",
                  value: theme.bottomBarBlur,
                  min: 0.0,
                  max: 20.0,
                  divisions: 40,
                  onChanged: (value) => theme.setBottomBarBlur(value),
                  displayValue: theme.bottomBarBlur.toStringAsFixed(1),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeManagementSection extends StatelessWidget {
  const _ThemeManagementSection();

  void _showSaveThemeDialog(BuildContext context, ThemeProvider theme) {
    final controller = TextEditingController(
      text: "Копия ${theme.activeTheme.name}",
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Сохранить тему"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: "Название темы"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Отмена"),
            ),
            TextButton(
              onPressed: () {
                theme.saveCurrentThemeAs(controller.text);
                Navigator.of(context).pop();
              },
              child: const Text("Сохранить"),
            ),
          ],
        );
      },
    );
  }

  void _showConfirmDeleteDialog(
    BuildContext context,
    ThemeProvider theme,
    CustomThemePreset preset,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Удалить тему?"),
          content: Text("Вы уверены, что хотите удалить '${preset.name}'?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Отмена"),
            ),
            TextButton(
              onPressed: () {
                theme.deleteTheme(preset.id);
                Navigator.of(context).pop();
              },
              child: const Text("Удалить", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showRenameDialog(
    BuildContext context,
    ThemeProvider theme,
    CustomThemePreset preset,
  ) {
    final controller = TextEditingController(text: preset.name);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Переименовать тему"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: "Новое название"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Отмена"),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  theme.renameTheme(preset.id, controller.text);
                  Navigator.of(context).pop();
                }
              },
              child: const Text("Сохранить"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _doExport(
    BuildContext context,
    ThemeProvider theme,
    CustomThemePreset preset,
  ) async {
    try {
      final String jsonString = jsonEncode(preset.toJson());
      final String fileName =
          '${preset.name.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_')}.ktheme';

      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить тему...',
        fileName: fileName,
        allowedExtensions: ['ktheme'],
        type: FileType.custom,
      );

      if (outputFile != null) {
        if (!outputFile.endsWith('.ktheme')) {
          outputFile += '.ktheme';
        }

        final file = File(outputFile);
        await file.writeAsString(jsonString);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Тема "${preset.name}" экспортирована.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка экспорта: $e')));
      }
    }
  }

  Future<void> _doImport(BuildContext context, ThemeProvider theme) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ktheme'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();

        final bool success = await theme.importThemeFromJson(jsonString);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Тема успешно импортирована!'
                    : 'Ошибка: Неверный формат файла темы.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка импорта: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = Theme.of(context).colorScheme;

    return _ModernSection(
      title: "Пресеты тем",
      children: [
        ...theme.savedThemes.map((preset) {
          final bool isActive = theme.activeTheme.id == preset.id;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(
              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isActive ? colors.primary : colors.onSurfaceVariant,
            ),
            title: Text(
              preset.name,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (preset.id != 'default')
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: "Переименовать",
                    onPressed: () => _showRenameDialog(context, theme, preset),
                  ),

                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: "Экспорт",
                  onPressed: () => _doExport(context, theme, preset),
                ),
                if (preset.id != 'default')
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: "Удалить",
                    onPressed: () =>
                        _showConfirmDeleteDialog(context, theme, preset),
                  ),
              ],
            ),
            onTap: () {
              if (!isActive) {
                theme.applyTheme(preset.id);
              }
            },
          );
        }),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Сохранить"),
              onPressed: () => _showSaveThemeDialog(context, theme),
            ),
            TextButton.icon(
              icon: const Icon(Icons.file_download_outlined),
              label: const Text("Импорт"),
              onPressed: () => _doImport(context, theme),
            ),
          ],
        ),
      ],
    );
  }
}

class _ModernSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ModernSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 12.0),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.outlineVariant.withOpacity(0.3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class _CustomSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  const _CustomSettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        child,
      ],
    );
  }
}

class _ColorPickerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const _ColorPickerTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showColorPicker(
        context,
        initialColor: color,
        onColorChanged: onColorChanged,
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            const Icon(Icons.color_lens_outlined),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData? icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final String displayValue;

  const _SliderTile({
    this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 14)),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 30,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class AppThemeSelector extends StatelessWidget {
  final AppTheme selectedTheme;
  final ValueChanged<AppTheme> onChanged;

  const AppThemeSelector({
    super.key,
    required this.selectedTheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ThemeButton(
          theme: AppTheme.system,
          selectedTheme: selectedTheme,
          onChanged: onChanged,
          icon: Icons.brightness_auto_outlined,
          label: "Система",
        ),
        _ThemeButton(
          theme: AppTheme.light,
          selectedTheme: selectedTheme,
          onChanged: onChanged,
          icon: Icons.light_mode_outlined,
          label: "Светлая",
        ),
        _ThemeButton(
          theme: AppTheme.dark,
          selectedTheme: selectedTheme,
          onChanged: onChanged,
          icon: Icons.dark_mode_outlined,
          label: "Тёмная",
        ),
        _ThemeButton(
          theme: AppTheme.black,
          selectedTheme: selectedTheme,
          onChanged: onChanged,
          icon: Icons.dark_mode,
          label: "OLED",
        ),
      ],
    );
  }
}

class _ThemeButton extends StatelessWidget {
  final AppTheme theme;
  final AppTheme selectedTheme;
  final ValueChanged<AppTheme> onChanged;
  final IconData icon;
  final String label;

  const _ThemeButton({
    required this.theme,
    required this.selectedTheme,
    required this.onChanged,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isSelected = selectedTheme == theme;

    return GestureDetector(
      onTap: () => onChanged(theme),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 70,
        height: 70,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primaryContainer
              : colors.surfaceVariant.withOpacity(0.3),
          border: Border.all(
            color: isSelected ? colors.primary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? colors.onPrimaryContainer
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePreviewSection extends StatelessWidget {
  const _MessagePreviewSection();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = Theme.of(context).colorScheme;
    final mockMyMessage = Message(
      id: '1',
      senderId: 100,
      text: "Выглядит отлично! 🔥",
      time: DateTime.now().millisecondsSinceEpoch,
      attaches: const [],
    );
    final mockTheirMessage = Message(
      id: '2',
      senderId: 200,
      text: "Привет! Как тебе новый вид?",
      time: DateTime.now().millisecondsSinceEpoch,
      attaches: const [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 12.0),
          child: Text(
            "ПРЕДПРОСМОТР",
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant.withOpacity(0.3)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              children: [
                const _ChatWallpaperPreview(),
                Column(
                  children: [
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: theme.useGlassPanels ? theme.topBarBlur : 0,
                          sigmaY: theme.useGlassPanels ? theme.topBarBlur : 0,
                        ),
                        child: Container(
                          height: 40,
                          color: colors.surface.withOpacity(
                            theme.useGlassPanels ? theme.topBarOpacity : 0.0,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              CircleAvatar(
                                backgroundColor: colors.primaryContainer,
                                radius: 12,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colors.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ChatMessageBubble(
                        message: mockTheirMessage,
                        isMe: false,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ChatMessageBubble(
                        message: mockMyMessage,
                        isMe: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: theme.useGlassPanels
                              ? theme.bottomBarBlur
                              : 0,
                          sigmaY: theme.useGlassPanels
                              ? theme.bottomBarBlur
                              : 0,
                        ),
                        child: Container(
                          height: 40,
                          color: colors.surface.withOpacity(
                            theme.useGlassPanels ? theme.bottomBarOpacity : 0.0,
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: colors.surfaceVariant,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.send, color: colors.primary),
                              const SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatWallpaperPreview extends StatelessWidget {
  const _ChatWallpaperPreview();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;

    if (!theme.useCustomChatWallpaper) {
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    switch (theme.chatWallpaperType) {
      case ChatWallpaperType.solid:
        return Container(color: theme.chatWallpaperColor1);
      case ChatWallpaperType.gradient:
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.chatWallpaperColor1, theme.chatWallpaperColor2],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        );
      case ChatWallpaperType.image:
        if (theme.chatWallpaperImagePath?.isNotEmpty == true) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(theme.chatWallpaperImagePath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Center(child: Icon(Icons.error)),
              ),
              if (theme.chatWallpaperImageBlur > 0)
                BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: theme.chatWallpaperImageBlur,
                    sigmaY: theme.chatWallpaperImageBlur,
                  ),
                  child: Container(color: Colors.black.withOpacity(0.05)),
                ),
            ],
          );
        } else {
          return Container(
            color: isDarkTheme ? Colors.grey[850] : Colors.grey[200],
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: isDarkTheme ? Colors.grey[600] : Colors.grey[400],
                size: 40,
              ),
            ),
          );
        }
      case ChatWallpaperType.video:

        if (Platform.isWindows) {
          return Container(
            color: isDarkTheme ? Colors.grey[850] : Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library_outlined,
                    color: isDarkTheme ? Colors.grey[600] : Colors.grey[400],
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Видео-обои\nне поддерживаются на Windows',
                    style: TextStyle(
                      color: isDarkTheme ? Colors.grey[600] : Colors.grey[400],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        if (theme.chatWallpaperVideoPath?.isNotEmpty == true) {
          return _VideoWallpaper(path: theme.chatWallpaperVideoPath!);
        } else {
          return Container(
            color: isDarkTheme ? Colors.grey[850] : Colors.grey[200],
            child: Center(
              child: Icon(
                Icons.video_library_outlined,
                color: isDarkTheme ? Colors.grey[600] : Colors.grey[400],
                size: 40,
              ),
            ),
          );
        }
    }
  }
}

class _VideoWallpaper extends StatefulWidget {
  final String path;

  const _VideoWallpaper({required this.path});

  @override
  State<_VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<_VideoWallpaper> {
  VideoPlayerController? _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      final file = File(widget.path);
      if (!await file.exists()) {
        setState(() {
          _errorMessage = 'Video file not found';
        });
        print('ERROR: Video file does not exist: ${widget.path}');
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();

      if (mounted) {
        _controller!.setVolume(0);
        _controller!.setLooping(true);
        _controller!.play();
        setState(() {});
        print('SUCCESS: Video initialized and playing');
      }
    } catch (e) {
      print('ERROR initializing video: $e');
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      print('ERROR building video widget: $_errorMessage');
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: VideoPlayer(_controller!),
            ),
          ),
        ),

        Container(
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.3)),
        ),
      ],
    );
  }
}
