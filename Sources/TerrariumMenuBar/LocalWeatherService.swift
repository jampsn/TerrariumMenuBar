import Foundation

struct LocalWeatherReading: Equatable {
    let tempC: Int
    let city: String
    let fetchedAt: Date
}

/// 零系统弹窗的本地气象服务（HTTPS 自动 IP 定位 + Open-Meteo 实时气温，断网自动回退）
enum LocalWeatherService {
    private struct GeoJSResponse: Decodable {
        let latitude: String?
        let longitude: String?
        let city: String?
    }

    private struct IPWhoResponse: Decodable {
        let success: Bool?
        let latitude: Double?
        let longitude: Double?
        let city: String?
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
        }
        let current: Current
    }

    static func fetchCurrentLocalTemperature() async -> LocalWeatherReading? {
        guard let loc = await fetchLocation() else { return nil }
        let urlString = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m&timezone=auto",
            loc.lat,
            loc.lon
        )
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let rounded = Int(decoded.current.temperature_2m.rounded())
            return LocalWeatherReading(tempC: rounded, city: loc.city, fetchedAt: Date())
        } catch {
            return nil
        }
    }

    private static func fetchLocation() async -> (lat: Double, lon: Double, city: String)? {
        if let primary = await fetchFromGeoJS() {
            return primary
        }
        return await fetchFromIPWho()
    }

    private static func fetchFromGeoJS() async -> (lat: Double, lon: Double, city: String)? {
        guard let url = URL(string: "https://get.geojs.io/v1/ip/geo.json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(GeoJSResponse.self, from: data)
            guard let latStr = decoded.latitude, let lonStr = decoded.longitude,
                  let lat = Double(latStr), let lon = Double(lonStr) else {
                return nil
            }
            let city = decoded.city?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (lat, lon, (city?.isEmpty == false) ? city! : "本地")
        } catch {
            return nil
        }
    }

    private static func fetchFromIPWho() async -> (lat: Double, lon: Double, city: String)? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(IPWhoResponse.self, from: data)
            guard decoded.success != false, let lat = decoded.latitude, let lon = decoded.longitude else {
                return nil
            }
            let city = decoded.city?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (lat, lon, (city?.isEmpty == false) ? city! : "本地")
        } catch {
            return nil
        }
    }
}
