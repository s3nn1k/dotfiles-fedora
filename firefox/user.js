// Firefox: prefs для снижения потребления RAM (Firefox 150, Fedora rpm).
// user.js перечитывается при каждом старте браузера; значения прилипчивые -
// переопределяют ручные правки в about:config.
// Формат строк ниже: дефолт -> значение: суть настройки.

user_pref("dom.ipc.processCount", 4);                                   // 8 -> 4: кап процессов контента без изоляции
user_pref("dom.ipc.processCount.webIsolated", 2);                       // 4 -> 2: кап процессов контента при Fission, главный процессный рычаг
user_pref("dom.ipc.processPrelaunch.fission.number", 1);                // 3 -> 1: меньше прогретых запасных процессов
user_pref("browser.tabs.unloadOnLowMemory", true);                      // false (на Win/macOS true) -> true: выгрузка неактивных табов при нехватке памяти
user_pref("browser.tabs.min_inactive_duration_before_unload", 600000);  // 600000 (дефолт): таб младше 10 минут не выгружается
user_pref("browser.sessionhistory.max_total_viewers", 1);               // -1 (авто, при RAM >= 1GB даёт 8) -> 1: копии страниц для back/forward
user_pref("browser.cache.memory.capacity", 262144);                     // -1 (авто, растёт с RAM) -> 262144: потолок HTTP-кэша в памяти в КБ, 256 МБ
user_pref("image.mem.surfacecache.size_factor", 8);                     // 4 -> 8: бюджет surface-кэша картинок 1/8 RAM вместо 1/4
user_pref("media.memory_caches_combined_limit_kb", 262144);             // 524288 -> 262144: потолок медиа-буферов в КБ
user_pref("browser.sessionstore.max_tabs_undo", 5);                     // 25 -> 5: закрытые табы в памяти для ctrl+shift+T

// Телеметрия и фоновые отчёты: пинги и фоновые загрузки данных в Mozilla.
user_pref("datareporting.policy.dataSubmissionEnabled", false);                         // true -> false: мастер-выключатель загрузки данных Mozilla, гасит и DAU-пинг
user_pref("datareporting.healthreport.uploadEnabled", false);                           // true -> false: выгрузка healthreport в Mozilla
user_pref("toolkit.telemetry.unified", false);                                          // true -> false: главный тумблер унифицированной телеметрии
user_pref("toolkit.telemetry.archive.enabled", false);                                  // true -> false: локальный архив телеметрии
user_pref("browser.tabs.crashReporting.sendReport", false);                             // true -> false: отчёт о падении таба в Mozilla
user_pref("app.shield.optoutstudies.enabled", false);                                   // true -> false: эксперименты Shield
user_pref("browser.discovery.enabled", false);                                          // true -> false: рекомендуемые расширения на about:addons
user_pref("browser.ml.chat.enabled", false);                                            // true -> false: кнопки AI-чатов

// Спонсорские подсказки: sponsored-подсказки urlbar и спонсорский контент новой вкладки.
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);                      // false (sticky-дефолт) -> false: закрепление без спонсорских подсказок urlbar
user_pref("browser.newtabpage.activity-stream.showSponsored", false);                   // true -> false: спонсорский контент на новой вкладке
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);           // true -> false: спонсорские плитки топ-сайтов

// Стартовый шум и UI: онбординг, промо-блоки, фоновые пробы сети.
user_pref("browser.aboutwelcome.enabled", false);                                       // true -> false: онбординг при первом запуске
user_pref("browser.startup.homepage_override.mstone", "ignore");                        // не задан (пишется после апдейта) -> "ignore": подавить страницу "что нового"
user_pref("browser.shell.checkDefaultBrowser", false);                                  // true -> false: проверка дефолтного браузера при старте
user_pref("browser.preferences.moreFromMozilla", false);                                // true -> false: промо-блок "Больше от Mozilla" в настройках
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);   // true -> false: советы-рекомендации расширений в UI
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false); // true -> false: советы о функциях в UI
user_pref("network.captive-portal-service.enabled", false);                             // true -> false: фоновая проба captive portal
user_pref("network.connectivity-service.enabled", false);                               // true -> false: фоновая проба связности
user_pref("captivedetect.canonicalURL", "");                                            // detectportal.firefox.com/canonical.html -> "": URL пробы captive portal
user_pref("browser.uidensity", 1);                                                      // 0 (обычная) -> 1: компактная плотность UI

// Агрессивные опции: каждая с трейдоффом, включается снятием // перед строкой.
// user_pref("fission.autostart", false);                                // true -> false: минус site isolation - сайты делят процессы (риск Spectre-класса), официально непроверяемый путь; при webIsolated=2 экономия минимальна
// user_pref("dom.ipc.processCount", 2);                                // 4 -> 2: ещё меньше процессов, ценой взаимных тормозов табов
// user_pref("browser.tabs.min_inactive_duration_before_unload", 300000); // 600000 -> 300000: выгрузка неактивного таба уже через 5 минут
