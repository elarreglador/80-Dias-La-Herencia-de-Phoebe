import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/fatigue.dart';
import '../../utils/app_colors.dart';

/// Tarjeta independiente de descanso en hotel — primera opción de la lista
/// de llegada.
///
/// Es una acción sobre la ciudad actual, no un destino ni un vehículo, por lo
/// que no vive dentro de [DestinationCard]; se muestra como la primera opción
/// disponible en el estado «en destino».
///
/// El botón «Ir al Hotel a descansar» se deshabilita automáticamente después
/// de la primera pulsación para evitar gastos repetidos del presupuesto.
class HotelRestCard extends StatefulWidget {
  const HotelRestCard({
    super.key,
    required this.onRestAtHotel,
    required this.hotelPrice,
    required this.fatigue,
    required this.isRestingAtHotel,
  });

  final VoidCallback onRestAtHotel;
  final int? hotelPrice;
  final Fatigue fatigue;
  final bool isRestingAtHotel;

  @override
  State<HotelRestCard> createState() => _HotelRestCardState();
}

class _HotelRestCardState extends State<HotelRestCard> {
  bool _pressed = false;
  late String _restStatusMessage;

  @override
  void initState() {
    super.initState();
    _restStatusMessage = widget.isRestingAtHotel
        ? 'Descansando en el hotel...'
        : widget.fatigue.mustSleep
            ? 'Phoebe está agotada: debe descansar antes de continuar'
            : 'Descanso en hotel: recuperación ${Fatigue.hotelRecoverRate}%/h';
  }

  void _doRest() {
    if (_pressed) return;
    _pressed = true;
    widget.onRestAtHotel();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.foggRed.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('hotel-rest-card'),
        onTap: _pressed ? null : _doRest,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.hotel, size: 22, color: AppColors.foggRed),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Ir al Hotel a descansar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.labelColor,
                      ),
                    ),
                  ),
                  if (widget.hotelPrice != null)
                    Text(
                      '${widget.hotelPrice}€',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foggRed,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _restStatusMessage,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.labelColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
