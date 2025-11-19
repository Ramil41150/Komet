
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gwid/api/api_service.dart';
import 'package:gwid/models/profile.dart';
import 'package:gwid/phone_entry_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ManageAccountScreen extends StatefulWidget {
  final Profile? myProfile;
  const ManageAccountScreen({super.key, this.myProfile});

  @override
  State<ManageAccountScreen> createState() => _ManageAccountScreenState();
}

class _ManageAccountScreenState extends State<ManageAccountScreen> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _descriptionController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(
      text: widget.myProfile?.firstName ?? '',
    );
    _lastNameController = TextEditingController(
      text: widget.myProfile?.lastName ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.myProfile?.description ?? '',
    );
  }

  void _saveProfile() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    ApiService.instance.updateProfileText(
      _firstNameController.text.trim(),
      _lastNameController.text.trim(),
      _descriptionController.text.trim(),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Профиль успешно сохранен"),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
            ),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ApiService.instance.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const PhoneEntryScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка выхода: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _pickAndUpdateProfilePhoto() async {
    final ImagePicker picker = ImagePicker();

    final XFile? image = await picker.pickImage(source: ImageSource.gallery);


    if (image != null) {

      File imageFile = File(image.path);






      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Фотография профиля обновляется..."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Изменить профиль"),
        centerTitle: true,
        scrolledUnderElevation: 0,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: const Text(
              "Сохранить",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAvatarSection(theme),
              const SizedBox(height: 32),


              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Основная информация",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _firstNameController,
                        maxLength: 60, // Ограничение по символам
                        decoration: _buildInputDecoration(
                          "Имя",
                          Icons.person_outline,
                        ).copyWith(counterText: ""), // Скрываем счетчик
                        validator: (value) =>
                            value!.isEmpty ? 'Введите ваше имя' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _lastNameController,
                        maxLength: 60, // Ограничение по символам
                        decoration: _buildInputDecoration(
                          "Фамилия",
                          Icons.person_outline,
                        ).copyWith(counterText: ""), // Скрываем счетчик
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),


              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Дополнительно",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        maxLength: 400,
                        decoration: _buildInputDecoration(
                          "О себе",
                          Icons.edit_note_outlined,
                          alignLabel: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),


              if (widget.myProfile != null)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildInfoTile(
                        icon: Icons.phone_outlined,
                        title: "Телефон",
                        subtitle: widget.myProfile!.formattedPhone,
                      ),
                      const Divider(height: 1),
                      _buildTappableInfoTile(
                        icon: Icons.tag,
                        title: "Ваш ID",
                        subtitle: widget.myProfile!.id.toString(),
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(
                              text: widget.myProfile!.id.toString(),
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ID скопирован в буфер обмена'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildAvatarSection(ThemeData theme) {
    return Center(
      child: GestureDetector(

        onTap: _pickAndUpdateProfilePhoto, // 2. Вызываем метод при нажатии
        child: Stack(
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: theme.colorScheme.secondaryContainer,
              backgroundImage: widget.myProfile?.photoBaseUrl != null
                  ? NetworkImage(widget.myProfile!.photoBaseUrl!)
                  : null,
              child: widget.myProfile?.photoBaseUrl == null
                  ? Icon(
                      Icons.person,
                      size: 60,
                      color: theme.colorScheme.onSecondaryContainer,
                    )
                  : null,
            ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(
    String label,
    IconData icon, {
    bool alignLabel = false,
  }) {

    final prefixIcon = (label == "О себе")
        ? Padding(
            padding: const EdgeInsets.only(bottom: 60), // Смещаем иконку вверх
            child: Icon(icon),
          )
        : Icon(icon);

    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      alignLabelWithHint: alignLabel,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
    );
  }

  Widget _buildTappableInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.copy_outlined, size: 20),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.logout),
      label: const Text('Выйти из аккаунта'),
      onPressed: _logout,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red.shade400,
        side: BorderSide(color: Colors.red.shade200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
