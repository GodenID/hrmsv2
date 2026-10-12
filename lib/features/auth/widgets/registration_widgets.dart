import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';

/// Pilihan tunggal berbentuk baris bergaris (radio), mis. jenis kelamin &
/// divisi. Terpilih = garis aksen + latar aksen tipis + titik radio.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.hasError = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final borderColor = selected
        ? context.accentText
        : hasError
        ? context.danger
        : context.borderStrong;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? context.accentSubtle : context.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: borderColor, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  if (icon != null) ...[
                    AnimatedContainer(
                      duration: duration,
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selected
                            ? context.surface
                            : context.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFFC6DDDA)
                              : context.border,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: selected
                            ? context.accentText
                            : context.inkSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: context.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _RadioMark(selected: selected, duration: duration),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.selected, required this.duration});

  final bool selected;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.surface,
        border: Border.all(
          color: selected ? context.accentText : context.borderStrong,
          width: selected ? 5 : 1.6,
        ),
      ),
    );
  }
}

/// Grup [ChoiceTile] sebagai field formulir (ikut validasi [Form]).
class ChoiceFormField<T extends Object> extends FormField<T> {
  ChoiceFormField({
    super.key,
    required List<T> options,
    required String Function(T option) labelOf,
    required ValueChanged<T> onChanged,
    IconData Function(T option)? iconOf,
    super.initialValue,
    super.validator,
    super.enabled,
    int columns = 1,
  }) : super(
         builder: (field) {
           final errorStyle = Theme.of(field.context)
               .inputDecorationTheme
               .errorStyle;
           Widget tile(T option) => ChoiceTile(
             label: labelOf(option),
             icon: iconOf?.call(option),
             selected: field.value == option,
             hasError: field.hasError,
             onTap: field.widget.enabled
                 ? () {
                     field.didChange(option);
                     onChanged(option);
                   }
                 : null,
           );

           final rows = <Widget>[];
           for (var i = 0; i < options.length; i += columns) {
             final chunk = options.sublist(
               i,
               (i + columns).clamp(0, options.length),
             );
             if (rows.isNotEmpty) {
               rows.add(const SizedBox(height: AppSpacing.sm));
             }
             rows.add(
               columns == 1
                   ? tile(chunk.single)
                   : Row(
                       children: [
                         for (var j = 0; j < columns; j++) ...[
                           if (j > 0) const SizedBox(width: AppSpacing.sm),
                           Expanded(
                             child: j < chunk.length
                                 ? tile(chunk[j])
                                 : const SizedBox.shrink(),
                           ),
                         ],
                       ],
                     ),
             );
           }

           return Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             mainAxisSize: MainAxisSize.min,
             children: [
               ...rows,
               if (field.hasError)
                 Padding(
                   padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                   child: Semantics(
                     liveRegion: true,
                     child: Text(field.errorText!, style: errorStyle),
                   ),
                 ),
             ],
           );
         },
       );
}

/// Kotak abu muda untuk sub-bagian formulir (mis. kontak darurat).
class FormSubsection extends StatelessWidget {
  const FormSubsection({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: context.accentText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

/// Ringkasan satu kategori data di langkah "Tinjau", dengan tombol "Ubah".
class ReviewSection extends StatelessWidget {
  const ReviewSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.onEdit,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
            decoration: BoxDecoration(
              color: context.surfaceMuted,
              border: Border(bottom: BorderSide(color: context.border)),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.panel - 1),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: context.inkSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title.toUpperCase(),
                      style: textTheme.labelSmall,
                    ),
                  ),
                ),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text('Ubah', semanticsLabel: 'Ubah $title'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ringkasan Kebijakan Privasi & Syarat Ketentuan pendaftaran akun.
/// Isi lengkap dokumen resmi dikelola Tim HR; teks ini menjelaskan garis
/// besarnya agar persetujuan pendaftar bermakna (UU No. 27 Tahun 2022
/// tentang Pelindungan Data Pribadi).
Future<void> showPrivacyPolicyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Kebijakan Privasi & Syarat Ketentuan'),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PolicySection(
              title: 'Data yang dikumpulkan',
              body:
                  'Nama, NIK, tempat & tanggal lahir, alamat, email, nomor HP, '
                  'kontak darurat, dan divisi — sesuai yang Anda isi di '
                  'formulir pendaftaran.',
            ),
            _PolicySection(
              title: 'Tujuan penggunaan',
              body:
                  'Verifikasi identitas, administrasi kepegawaian, absensi, '
                  'dan komunikasi resmi terkait pekerjaan. Data tidak dipakai '
                  'untuk keperluan lain tanpa persetujuan Anda.',
            ),
            _PolicySection(
              title: 'Penyimpanan & keamanan',
              body:
                  'Password disimpan dalam bentuk hash. NIK lengkap dan data '
                  'pribadi hanya dapat dilihat Tim HR dan atasan yang '
                  'berwenang, tidak ditampilkan ke karyawan lain.',
            ),
            _PolicySection(
              title: 'Hak Anda',
              body:
                  'Anda berhak mengakses, memperbaiki, dan meminta penghapusan '
                  'data pribadi Anda, serta menarik persetujuan ini kapan '
                  'saja melalui Tim HR.',
            ),
            _PolicySection(
              title: 'Penarikan persetujuan',
              body:
                  'Persetujuan ini wajib untuk membuat akun. Bila ditarik, '
                  'akun tidak dapat diproses dan akan dinonaktifkan sesuai '
                  'ketentuan perusahaan.',
            ),
            _PolicySection(
              title: 'Kontak',
              body:
                  'Pertanyaan soal data pribadi: hubungi Tim HR Prasasti Group.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(body, style: textTheme.bodySmall?.copyWith(height: 1.5)),
        ],
      ),
    );
  }
}

/// Baris label–nilai ringkasan. Nilai bisa berupa teks atau widget
/// (mis. badge role).
class ReviewRow extends StatelessWidget {
  const ReviewRow({
    super.key,
    required this.label,
    this.value,
    this.valueWidget,
  }) : assert(value != null || valueWidget != null);

  final String label;
  final String? value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final valueChild =
        valueWidget ??
        Text(
          value!,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelText = Text(label, style: textTheme.bodySmall);
            if (constraints.maxWidth < 300) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 2), valueChild],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 112, child: labelText),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: valueChild,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
