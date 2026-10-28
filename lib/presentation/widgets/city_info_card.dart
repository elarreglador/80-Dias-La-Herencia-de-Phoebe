import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/fogg_city.dart';
import '../../services/timezone_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/weather_formatter.dart';
import '../providers/bottom_nav_provider.dart';
import '../providers/map_focus_provider.dart';
import '../providers/route_catalog_provider.dart';
import '../providers/time_engine_provider.dart';

/// Tarjeta de contexto de la ciudad actual — imagen, hora local y acceso al mapa.
///
/// La hora civil se deriva del reloj de la partida ([timeEngineProvider]) y de
/// la zona IANA de la ciudad, nunca del reloj del dispositivo. El widget
/// observa el provider, así que se repinta cuando el reloj avanza; no crea
/// ningún `Timer` propio.
class CityInfoCard extends ConsumerWidget {
  const CityInfoCard({super.key, required this.city});

  final FoggCity city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTime = ref.watch(timeEngineProvider).now();
    final localTime = TimezoneService.formatLocalTime(
      currentTime,
      city.timezone,
    );
    final weatherService = ref.watch(weatherServiceProvider);
    final snapshot = weatherService.fetchSync(city.lat, city.lng, currentTime);
    final weatherSummary = formatWeatherSummary(snapshot);

    return ClipRRect(
      key: const ValueKey('city-info-card'),
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: AppColors.surface,
        child: SizedBox(
          height: 210,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/ciudad_generica.jpg',
                fit: BoxFit.cover,
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  key: const ValueKey('city-info-strip'),
                  width: double.infinity,
                  color: AppColors.surface.withValues(alpha: 0.78),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 22,
                        color: AppColors.foggRed.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            localTime,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.labelColor,
                            ),
                          ),
                          Text(
                            'hora local',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.labelColor.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Tooltip(
                        message: 'Ver ${city.name} en el mapa',
                        child: Material(
                          color: Colors.transparent,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              ref.read(mapFocusProvider.notifier).request(city, zoom: 7.0);
                              ref.read(bottomNavIndexProvider.notifier).state = 0;
                            },
                            customBorder: const StadiumBorder(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 22,
                                    color: AppColors.foggRed,
                                    semanticLabel: 'Ver ${city.name} en el mapa',
                                  ),
                                   const SizedBox(width: 4),
                                   Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     mainAxisSize: MainAxisSize.min,
                                     children: [
                                       Text(
                                         city.name,
                                         style: const TextStyle(
                                           fontSize: 15,
                                           fontWeight: FontWeight.w700,
                                           color: AppColors.labelColor,
                                         ),
                                       ),
                                       if (weatherSummary != null)
                                         Text(
                                           weatherSummary,
                                           style: TextStyle(
                                             fontSize: 11,
                                             color: AppColors.labelColor.withValues(alpha: 0.7),
                                           ),
                                         ),
                                     ],
                                   ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
