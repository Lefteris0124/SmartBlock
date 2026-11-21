import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as material;

import 'app_language.dart';

/// Translates common, static interface labels while retaining dynamic content.
/// Each screen can be migrated to generated ARB localization incrementally.
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String? data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<SmartBlockLanguage>(
        valueListenable: SmartBlockLanguageController.instance.selected,
        builder: (context, language, _) => material.Text(
          _translate(data, language.code) ?? '',
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        ),
      );

  static String? _translate(String? value, String code) {
    if (value == null || code == 'el' || code == 'en') return value;
    return _translations[value]?[code] ?? value;
  }

  static const _translations = <String, Map<String, String>>{
    'Save': {
      'ru': 'Сохранить',
      'uk': 'Зберегти',
      'ro': 'Salvează',
      'he': 'שמור',
    },
    'Cancel': {
      'ru': 'Отмена',
      'uk': 'Скасувати',
      'ro': 'Anulează',
      'he': 'ביטול',
    },
    'Close': {'ru': 'Закрыть', 'uk': 'Закрити', 'ro': 'Închide', 'he': 'סגור'},
    'Back': {'ru': 'Назад', 'uk': 'Назад', 'ro': 'Înapoi', 'he': 'חזרה'},
    'Delete': {'ru': 'Удалить', 'uk': 'Видалити', 'ro': 'Șterge', 'he': 'מחק'},
    'Edit': {
      'ru': 'Изменить',
      'uk': 'Редагувати',
      'ro': 'Editează',
      'he': 'עריכה',
    },
    'Add': {'ru': 'Добавить', 'uk': 'Додати', 'ro': 'Adaugă', 'he': 'הוסף'},
    'Search': {'ru': 'Поиск', 'uk': 'Пошук', 'ro': 'Caută', 'he': 'חיפוש'},
    'Loading…': {
      'ru': 'Загрузка…',
      'uk': 'Завантаження…',
      'ro': 'Se încarcă…',
      'he': 'טוען…',
    },
    'Try again': {
      'ru': 'Повторить',
      'uk': 'Спробувати ще раз',
      'ro': 'Încearcă din nou',
      'he': 'נסה שוב',
    },
    'Retry': {
      'ru': 'Повторить',
      'uk': 'Повторити',
      'ro': 'Reîncearcă',
      'he': 'נסה שוב',
    },
    'Yes': {'ru': 'Да', 'uk': 'Так', 'ro': 'Da', 'he': 'כן'},
    'No': {'ru': 'Нет', 'uk': 'Ні', 'ro': 'Nu', 'he': 'לא'},
    'Name': {'ru': 'Имя', 'uk': 'Ім’я', 'ro': 'Nume', 'he': 'שם'},
    'Email': {
      'ru': 'Электронная почта',
      'uk': 'Електронна пошта',
      'ro': 'E-mail',
      'he': 'דוא״ל',
    },
    'Email address': {
      'ru': 'Электронная почта',
      'uk': 'Електронна пошта',
      'ro': 'Adresă de e-mail',
      'he': 'כתובת דוא״ל',
    },
    'Password': {'ru': 'Пароль', 'uk': 'Пароль', 'ro': 'Parolă', 'he': 'סיסמה'},
    'Description': {
      'ru': 'Описание',
      'uk': 'Опис',
      'ro': 'Descriere',
      'he': 'תיאור',
    },
    'Address': {'ru': 'Адрес', 'uk': 'Адреса', 'ro': 'Adresă', 'he': 'כתובת'},
    'Phone': {'ru': 'Телефон', 'uk': 'Телефон', 'ro': 'Telefon', 'he': 'טלפון'},
    'Status': {'ru': 'Статус', 'uk': 'Статус', 'ro': 'Stare', 'he': 'סטטוס'},
    'Active': {'ru': 'Активно', 'uk': 'Активно', 'ro': 'Activ', 'he': 'פעיל'},
    'Pending': {
      'ru': 'Ожидает',
      'uk': 'Очікує',
      'ro': 'În așteptare',
      'he': 'ממתין',
    },
    'Approved': {
      'ru': 'Одобрено',
      'uk': 'Схвалено',
      'ro': 'Aprobat',
      'he': 'אושר',
    },
    'Rejected': {
      'ru': 'Отклонено',
      'uk': 'Відхилено',
      'ro': 'Respins',
      'he': 'נדחה',
    },
    'Open': {'ru': 'Открыто', 'uk': 'Відкрито', 'ro': 'Deschis', 'he': 'פתוח'},
    'Closed': {'ru': 'Закрыто', 'uk': 'Закрито', 'ro': 'Închis', 'he': 'סגור'},
    'Properties': {
      'ru': 'Объекты',
      'uk': 'Нерухомість',
      'ro': 'Proprietăți',
      'he': 'נכסים',
    },
    'Property': {
      'ru': 'Объект',
      'uk': 'Об’єкт',
      'ro': 'Proprietate',
      'he': 'נכס',
    },
    'Owners': {
      'ru': 'Владельцы',
      'uk': 'Власники',
      'ro': 'Proprietari',
      'he': 'בעלים',
    },
    'Tenant': {
      'ru': 'Арендатор',
      'uk': 'Орендар',
      'ro': 'Chiriaș',
      'he': 'שוכר',
    },
    'Owner': {
      'ru': 'Владелец',
      'uk': 'Власник',
      'ro': 'Proprietar',
      'he': 'בעלים',
    },
    'Services': {
      'ru': 'Услуги',
      'uk': 'Послуги',
      'ro': 'Servicii',
      'he': 'שירותים',
    },
    'Service': {
      'ru': 'Услуга',
      'uk': 'Послуга',
      'ro': 'Serviciu',
      'he': 'שירות',
    },
    'Payments': {
      'ru': 'Платежи',
      'uk': 'Платежі',
      'ro': 'Plăți',
      'he': 'תשלומים',
    },
    'Finances': {
      'ru': 'Финансы',
      'uk': 'Фінанси',
      'ro': 'Finanțe',
      'he': 'כספים',
    },
    'Voting': {
      'ru': 'Голосование',
      'uk': 'Голосування',
      'ro': 'Vot',
      'he': 'הצבעות',
    },
    'Announcements': {
      'ru': 'Объявления',
      'uk': 'Оголошення',
      'ro': 'Anunțuri',
      'he': 'הודעות',
    },
    'Maintenance': {
      'ru': 'Обслуживание',
      'uk': 'Обслуговування',
      'ro': 'Mentenanță',
      'he': 'תחזוקה',
    },
    'Cleaning': {
      'ru': 'Уборка',
      'uk': 'Прибирання',
      'ro': 'Curățenie',
      'he': 'ניקיון',
    },
    'Emergency': {
      'ru': 'Аварийно',
      'uk': 'Невідкладно',
      'ro': 'Urgență',
      'he': 'חירום',
    },
    'Normal': {'ru': 'Обычно', 'uk': 'Звичайно', 'ro': 'Normal', 'he': 'רגיל'},
    'Urgent': {'ru': 'Срочно', 'uk': 'Терміново', 'ro': 'Urgent', 'he': 'דחוף'},
    'Send': {
      'ru': 'Отправить',
      'uk': 'Надіслати',
      'ro': 'Trimite',
      'he': 'שלח',
    },
    'Create': {'ru': 'Создать', 'uk': 'Створити', 'ro': 'Creează', 'he': 'צור'},
    'Create account': {
      'ru': 'Создать аккаунт',
      'uk': 'Створити обліковий запис',
      'ro': 'Creează un cont',
      'he': 'יצירת חשבון',
    },
    'Sign in': {
      'ru': 'Войти',
      'uk': 'Увійти',
      'ro': 'Autentificare',
      'he': 'התחברות',
    },
    'Sign out': {
      'ru': 'Выйти',
      'uk': 'Вийти',
      'ro': 'Deconectare',
      'he': 'התנתקות',
    },
    'Help': {'ru': 'Помощь', 'uk': 'Допомога', 'ro': 'Ajutor', 'he': 'עזרה'},
    'Chat': {'ru': 'Чат', 'uk': 'Чат', 'ro': 'Chat', 'he': 'צ׳אט'},
    'Settings': {
      'ru': 'Настройки',
      'uk': 'Налаштування',
      'ro': 'Setări',
      'he': 'הגדרות',
    },
    'Dashboard': {
      'ru': 'Панель управления',
      'uk': 'Панель керування',
      'ro': 'Panou de control',
      'he': 'לוח בקרה',
    },
    'Other': {'ru': 'Другое', 'uk': 'Інше', 'ro': 'Altele', 'he': 'אחר'},
    'Apartment': {
      'ru': 'Квартира',
      'uk': 'Квартира',
      'ro': 'Apartament',
      'he': 'דירה',
    },
    'Building': {
      'ru': 'Здание',
      'uk': 'Будівля',
      'ro': 'Clădire',
      'he': 'בניין',
    },
    'Monthly': {
      'ru': 'Ежемесячно',
      'uk': 'Щомісяця',
      'ro': 'Lunar',
      'he': 'חודשי',
    },
    'My properties': {
      'ru': 'Мои объекты',
      'uk': 'Моя нерухомість',
      'ro': 'Proprietățile mele',
      'he': 'הנכסים שלי',
    },
    'My apartment': {
      'ru': 'Моя квартира',
      'uk': 'Моя квартира',
      'ro': 'Apartamentul meu',
      'he': 'הדירה שלי',
    },
    'Property details': {
      'ru': 'Сведения об объекте',
      'uk': 'Відомості про об’єкт',
      'ro': 'Detalii proprietate',
      'he': 'פרטי הנכס',
    },
    'Property owner': {
      'ru': 'Владелец объекта',
      'uk': 'Власник нерухомості',
      'ro': 'Proprietarul imobilului',
      'he': 'בעל הנכס',
    },
    'Property owners': {
      'ru': 'Владельцы объекта',
      'uk': 'Власники нерухомості',
      'ro': 'Proprietarii imobilului',
      'he': 'בעלי הנכס',
    },
    'Apartment owner': {
      'ru': 'Владелец квартиры',
      'uk': 'Власник квартири',
      'ro': 'Proprietarul apartamentului',
      'he': 'בעל הדירה',
    },
    'Report a problem': {
      'ru': 'Сообщить о неисправности',
      'uk': 'Повідомити про несправність',
      'ro': 'Raportează o problemă',
      'he': 'דיווח על תקלה',
    },
    'No properties yet.': {
      'ru': 'Пока нет объектов.',
      'uk': 'Поки що немає нерухомості.',
      'ro': 'Nu există încă proprietăți.',
      'he': 'עדיין אין נכסים.',
    },
    'No owners have been added.': {
      'ru': 'Владельцы ещё не добавлены.',
      'uk': 'Власників ще не додано.',
      'ro': 'Nu au fost adăugați proprietari.',
      'he': 'עדיין לא נוספו בעלים.',
    },
    'No active owners found.': {
      'ru': 'Активные владельцы не найдены.',
      'uk': 'Активних власників не знайдено.',
      'ro': 'Nu au fost găsiți proprietari activi.',
      'he': 'לא נמצאו בעלים פעילים.',
    },
    'No pending reviews.': {
      'ru': 'Нет заявок на проверку.',
      'uk': 'Немає заявок на перевірку.',
      'ro': 'Nu există solicitări în așteptare.',
      'he': 'אין בקשות ממתינות לבדיקה.',
    },
    'No shared charges yet': {
      'ru': 'Общих расходов пока нет',
      'uk': 'Спільних витрат ще немає',
      'ro': 'Nu există încă cheltuieli comune',
      'he': 'עדיין אין חיובים משותפים',
    },
    'No payments recorded yet.': {
      'ru': 'Платежи ещё не зарегистрированы.',
      'uk': 'Платежі ще не зареєстровані.',
      'ro': 'Nu au fost înregistrate plăți.',
      'he': 'עדיין לא נרשמו תשלומים.',
    },
    'No support requests yet.': {
      'ru': 'Запросов в поддержку пока нет.',
      'uk': 'Запитів до підтримки ще немає.',
      'ro': 'Nu există încă solicitări de asistență.',
      'he': 'עדיין אין פניות לתמיכה.',
    },
    'Could not submit the report. Try again.': {
      'ru': 'Не удалось отправить сообщение. Попробуйте ещё раз.',
      'uk': 'Не вдалося надіслати повідомлення. Спробуйте ще раз.',
      'ro': 'Raportul nu a putut fi trimis. Încearcă din nou.',
      'he': 'לא ניתן לשלוח את הדיווח. נסה שוב.',
    },
    'Could not start secure checkout. Try again.': {
      'ru': 'Не удалось начать безопасную оплату. Попробуйте ещё раз.',
      'uk': 'Не вдалося розпочати безпечну оплату. Спробуйте ще раз.',
      'ro': 'Plata securizată nu a putut fi pornită. Încearcă din nou.',
      'he': 'לא ניתן להתחיל תשלום מאובטח. נסה שוב.',
    },
    'There are no manager requests.': {
      'ru': 'Запросов на назначение управляющего нет.',
      'uk': 'Запитів на призначення керуючого немає.',
      'ro': 'Nu există solicitări pentru administrator.',
      'he': 'אין בקשות למינוי מנהל.',
    },
    'Open a property to see its owners, votes, notices and finances.': {
      'ru': 'Откройте объект, чтобы увидеть владельцев, голосования, объявления и финансы.',
      'uk': 'Відкрийте нерухомість, щоб побачити власників, голосування, оголошення та фінанси.',
      'ro': 'Deschide proprietatea pentru a vedea proprietarii, voturile, anunțurile și finanțele.',
      'he': 'פתח את הנכס כדי לראות בעלים, הצבעות, הודעות וכספים.',
    },
    'Properties, owners, votes, notices and finances.': {
      'ru': 'Объекты, владельцы, голосования, объявления и финансы.',
      'uk': 'Нерухомість, власники, голосування, оголошення та фінанси.',
      'ro': 'Proprietăți, proprietari, voturi, anunțuri și finanțe.',
      'he': 'נכסים, בעלים, הצבעות, הודעות וכספים.',
    },
    'Could not open the secure checkout page.': {
      'ru': 'Не удалось открыть безопасную страницу оплаты.',
      'uk': 'Не вдалося відкрити безпечну сторінку оплати.',
      'ro': 'Pagina de plată securizată nu a putut fi deschisă.',
      'he': 'לא ניתן לפתוח את עמוד התשלום המאובטח.',
    },
    'Could not start payment.': {
      'ru': 'Не удалось начать оплату.',
      'uk': 'Не вдалося розпочати оплату.',
      'ro': 'Plata nu a putut fi pornită.',
      'he': 'לא ניתן להתחיל את התשלום.',
    },
    'No installments scheduled.': {
      'ru': 'Платежи по графику отсутствуют.',
      'uk': 'Платежів за графіком немає.',
      'ro': 'Nu există rate programate.',
      'he': 'אין תשלומים מתוזמנים.',
    },
    'No records yet.': {
      'ru': 'Записей пока нет.',
      'uk': 'Записів поки немає.',
      'ro': 'Nu există încă înregistrări.',
      'he': 'עדיין אין רשומות.',
    },
    'Apartment count': {
      'ru': 'Количество квартир',
      'uk': 'Кількість квартир',
      'ro': 'Număr de apartamente',
      'he': 'מספר דירות',
    },
    'Ownership percentage': {
      'ru': 'Доля владения',
      'uk': 'Частка власності',
      'ro': 'Cotă de proprietate',
      'he': 'אחוז בעלות',
    },
    'Area (m²)': {
      'ru': 'Площадь (м²)',
      'uk': 'Площа (м²)',
      'ro': 'Suprafață (m²)',
      'he': 'שטח (מ״ר)',
    },
    'Title deed': {
      'ru': 'Документ о праве собственности',
      'uk': 'Правовстановлювальний документ',
      'ro': 'Act de proprietate',
      'he': 'נסח טאבו',
    },
    'View deed': {
      'ru': 'Посмотреть документ',
      'uk': 'Переглянути документ',
      'ro': 'Vezi actul',
      'he': 'הצגת נסח',
    },
    'Sign up': {
      'ru': 'Зарегистрироваться',
      'uk': 'Зареєструватися',
      'ro': 'Înregistrare',
      'he': 'הרשמה',
    },
    'Forgot password?': {
      'ru': 'Забыли пароль?',
      'uk': 'Забули пароль?',
      'ro': 'Ai uitat parola?',
      'he': 'שכחת סיסמה?',
    },
    'Reset password': {
      'ru': 'Сбросить пароль',
      'uk': 'Скинути пароль',
      'ro': 'Resetează parola',
      'he': 'איפוס סיסמה',
    },
    'Create a property': {
      'ru': 'Создать объект',
      'uk': 'Створити нерухомість',
      'ro': 'Creează o proprietate',
      'he': 'יצירת נכס',
    },
    'Add property': {
      'ru': 'Добавить объект',
      'uk': 'Додати нерухомість',
      'ro': 'Adaugă proprietate',
      'he': 'הוספת נכס',
    },
    'Notices': {
      'ru': 'Объявления',
      'uk': 'Оголошення',
      'ro': 'Anunțuri',
      'he': 'הודעות',
    },
    'Common charges': {
      'ru': 'Общие расходы',
      'uk': 'Спільні витрати',
      'ro': 'Cheltuieli comune',
      'he': 'תשלומים משותפים',
    },
    'Rent': {'ru': 'Аренда', 'uk': 'Оренда', 'ro': 'Chirie', 'he': 'שכירות'},
    'Shared charges': {
      'ru': 'Общие расходы',
      'uk': 'Спільні витрати',
      'ro': 'Cheltuieli comune',
      'he': 'תשלומים משותפים',
    },
  };
}

