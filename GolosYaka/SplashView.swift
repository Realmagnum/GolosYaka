import SwiftUI

// КОМПОНЕНТ НЕОНОВО-ИНДИГОВОГО ОРЕОЛА (В ТОН ИКОНКИ NEURAL MIC)
struct PulsingHaloRing: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince1970
            let angle = (time * 160.0).truncatingRemainder(dividingBy: 360)
            let pulse = sin(time * 5.0) * 0.08 + 1.04

            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "#1E1B4B"),
                            Color(hex: "#4F46E5"),
                            Color(hex: "#38BDF8"),
                            Color(hex: "#A5F3FC"),
                            Color(hex: "#38BDF8"),
                            Color(hex: "#6366F1"),
                            Color(hex: "#1E1B4B")
                        ]),
                        center: .center,
                        angle: .degrees(angle)
                    ),
                    lineWidth: 10
                )
                .frame(width: 96, height: 96)
                .scaleEffect(pulse)
        }
    }
}

// БОКОВЫЕ ЗВУКОВЫЕ ДУГИ (ПОВТОРЯЮТ ГЕОМЕТРИЮ ИКОНКИ NEURAL MIC)
private struct SonicWaveArc: Shape {
    let startDegrees: Double
    let endDegrees: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        return path
    }
}

private struct SonicArcsOverlay: View {
    let innerScale: CGFloat
    let outerScale: CGFloat
    let innerOpacity: Double
    let outerOpacity: Double

    private var arcGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#818CF8").opacity(0.65),
                Color(hex: "#38BDF8"),
                Color(hex: "#A5F3FC")
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    var body: some View {
        ZStack {
            // Внутренняя пара дуг
            ZStack {
                SonicWaveArc(startDegrees: -38, endDegrees: 38)
                    .stroke(arcGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                SonicWaveArc(startDegrees: 142, endDegrees: 218)
                    .stroke(arcGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
            .frame(width: 126, height: 126)
            .scaleEffect(innerScale)
            .opacity(innerOpacity)

            // Внешняя пара дуг
            ZStack {
                SonicWaveArc(startDegrees: -34, endDegrees: 34)
                    .stroke(arcGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                SonicWaveArc(startDegrees: 146, endDegrees: 214)
                    .stroke(arcGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .frame(width: 162, height: 162)
            .scaleEffect(outerScale)
            .opacity(outerOpacity)
        }
        .shadow(color: Color(hex: "#38BDF8").opacity(0.45), radius: 10)
    }
}

/// Сплэш и стартовый аккорд — один раз на запущенный процесс.
///
/// Окно можно закрыть крестиком и открыть заново из статус-бара: это тот же
/// процесс, поэтому анимация и звук второй раз не проигрываются.
enum LaunchExperience {
    private(set) static var hasFinishedSplash = false

    static func markSplashFinished() {
        hasFinishedSplash = true
    }
}

struct SplashView: View {
    @Binding var isFinished: Bool

    // Иконка и импульс
    @State private var iconScale: CGFloat = 0.25
    @State private var iconOpacity: Double = 0.0
    @State private var iconRotationY: Double = -95
    @State private var iconTiltX: Double = 18

    // Акустические дуги и ударная волна
    @State private var innerArcScale: CGFloat = 0.72
    @State private var outerArcScale: CGFloat = 0.72
    @State private var innerArcOpacity: Double = 0.0
    @State private var outerArcOpacity: Double = 0.0
    @State private var shockwaveScale: CGFloat = 0.55
    @State private var shockwaveOpacity: Double = 0.0

    // Ореол
    @State private var haloScale: CGFloat = 0.2
    @State private var haloOpacity: Double = 0.0
    @State private var haloBlur: CGFloat = 18.0

    // Тексты и финальный переход
    @State private var logoOpacity: Double = 0.0
    @State private var logoOffset: CGFloat = 16
    @State private var perspective3D: Double = 35
    @State private var subtitleOpacity: Double = 0.0
    @State private var subtitleOffset: CGFloat = 10
    @State private var splashScale: CGFloat = 1.0
    @State private var splashBlur: CGFloat = 0.0

    // Фоновое сияние (индиго + циан)
    @State private var aurora1Offset: CGSize = CGSize(width: 90, height: -70)
    @State private var aurora2Offset: CGSize = CGSize(width: -90, height: 80)
    @State private var auroraOpacity: Double = 0.0

    var body: some View {
        ZStack {
            Color.uiCanvas.ignoresSafeArea()

            // Фоновая аврора в тонах новой иконки
            ZStack {
                Circle()
                    .fill(Color(hex: "#38BDF8").opacity(0.20))
                    .frame(width: 440, height: 440)
                    .offset(aurora1Offset)
                    .blur(radius: 95)

                Circle()
                    .fill(Color(hex: "#6366F1").opacity(0.22))
                    .frame(width: 520, height: 520)
                    .offset(aurora2Offset)
                    .blur(radius: 115)
            }
            .opacity(auroraOpacity)

            VStack(spacing: 30) {
                ZStack {
                    // Внешняя расходящаяся звуковая волна
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#38BDF8").opacity(0.55), Color(hex: "#6366F1").opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 96, height: 96)
                        .scaleEffect(shockwaveScale)
                        .opacity(shockwaveOpacity)

                    // Вращающийся неоново-индиговый ореол
                    PulsingHaloRing()
                        .blur(radius: haloBlur)
                        .scaleEffect(haloScale)
                        .opacity(haloOpacity)

                    // Боковые звуковые дуги вокруг микрофона
                    SonicArcsOverlay(
                        innerScale: innerArcScale,
                        outerScale: outerArcScale,
                        innerOpacity: innerArcOpacity,
                        outerOpacity: outerArcOpacity
                    )

                    // Иконка приложения
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .shadow(color: Color(hex: "#38BDF8").opacity(0.32), radius: 22, x: 0, y: 4)
                        .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
                        .scaleEffect(iconScale)
                        .opacity(iconOpacity)
                        .rotation3DEffect(.degrees(iconRotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                        .rotation3DEffect(.degrees(iconTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
                }
                .frame(height: 150)

                VStack(spacing: 14) {
                    Text("Г О Л О С Я К А")
                        .font(Font.custom("HelveticaNeue-UltraLight", size: 38))
                        .tracking(11.0)
                        .foregroundColor(.uiInk)
                        .opacity(logoOpacity)
                        .rotation3DEffect(.degrees(perspective3D), axis: (x: 1, y: 0, z: 0))
                        .offset(y: logoOffset)

                    VStack(spacing: 6) {
                        Text("Голосовой ввод и транскрибация на Вашем Mac")
                            .font(UIStyleFont.body(size: 13, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.uiMidGray)

                        Text("APPLE SILICON • GIGAAM V3 • NEURAL ENGINE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#0EA5E9"), Color(hex: "#6366F1")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .opacity(subtitleOpacity)
                    .offset(y: subtitleOffset)
                }
            }
            .scaleEffect(splashScale)
            .blur(radius: splashBlur)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            runMasterSequence()
            startAuroraBreathing()
        }
    }

    private func startAuroraBreathing() {
        withAnimation(.easeOut(duration: 0.45)) { auroraOpacity = 1.0 }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            aurora1Offset = CGSize(width: -75, height: 85)
            aurora2Offset = CGSize(width: 85, height: -75)
        }
    }

    private func runMasterSequence() {
        // 0.04s — Мгновенный старт: аккорд + 3D-появление иконки + внутренняя звуковая дуга
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            StartupSoundSynth.playTeslaChime()

            withAnimation(.spring(response: 0.46, dampingFraction: 0.72)) {
                iconScale = 1.0
                iconOpacity = 1.0
                iconRotationY = 0
                iconTiltX = 0

                haloScale = 1.15
                haloOpacity = 0.95
                haloBlur = 13.0

                innerArcScale = 1.0
                innerArcOpacity = 0.95

                logoOpacity = 1.0
                logoOffset = 0
                perspective3D = 0
            }

            withAnimation(.easeOut(duration: 0.75)) {
                shockwaveScale = 2.45
                shockwaveOpacity = 0.75
            }
        }

        // 0.24s — Расхождение внешней звуковой дуги и посадка ореола
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.68)) {
                outerArcScale = 1.0
                outerArcOpacity = 0.78
                haloScale = 1.0
                haloBlur = 9.0
            }
            withAnimation(.easeOut(duration: 0.45)) {
                shockwaveOpacity = 0.0
            }
        }

        // 0.36s — Быстрый выход подзаголовка и бейджа технологий
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                subtitleOpacity = 1.0
                subtitleOffset = 0
            }
        }

        // 1.05s — Второй лёгкий импульс звуковых дуг (живой отклик микрофона)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            withAnimation(.easeInOut(duration: 0.35)) {
                innerArcScale = 1.06
                outerArcScale = 1.09
                haloScale = 1.08
            }
        }

        // 1.60s — Стремительный кинематографичный переход в интерфейс
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.60) {
            withAnimation(.easeInOut(duration: 0.34)) {
                splashScale = 1.09
                splashBlur = 10.0
                auroraOpacity = 0.0
                haloOpacity = 0.0
                innerArcOpacity = 0.0
                outerArcOpacity = 0.0
            }
        }

        // 1.92s — Готово
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.92) {
            LaunchExperience.markSplashFinished()
            withAnimation(.easeOut(duration: 0.22)) { isFinished = true }
        }
    }
}
