import '../entities/fogg_city.dart';

/// Longitud desenrollada hacia el este respecto a [base].
///
/// Suma 360° hasta quedar estrictamente por encima de [base], de modo que
/// cruzar el antimeridiano hacia el este (Tokio → San Francisco) sigue siendo
/// "hacia el este". Es la base de la Regla del Este.
double unfoldLongitude(double lng, double base) {
  var x = lng;
  while (x <= base) {
    x += 360;
  }
  return x;
}

/// ¿[to] está al este de [from] según longitud desenrollada?
bool isEast(FoggCity from, FoggCity to) =>
    unfoldLongitude(to.lng, from.lng) > from.lng;

/// Distancia angular hacia el este de [from] a [to], en grados.
double eastDistance(FoggCity from, FoggCity to) =>
    (unfoldLongitude(to.lng, from.lng) - from.lng).abs();
