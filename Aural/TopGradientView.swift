//
//  TopGradientView.swift
//  Aural
//
//  Created by Rudrank Riyam on 8/17/25.
//

import SwiftUI

struct TopGradientView: View {
    @Environment(\.colorScheme) var scheme

    private let opacity: Double
    private let endPoint: UnitPoint

    init(opacity: Double = 0.64, endPoint: UnitPoint = .center) {
        self.opacity = opacity
        self.endPoint = endPoint
    }

    // Computed properties for dynamic shader parameters
    private var noiseIntensity: Float {
        scheme == .dark ? 0.4 : 0.2
    }

    private var noiseScale: Float {
        scheme == .dark ? 0.5 : 0.5
    }

    private var noiseFrequency: Float {
        scheme == .dark ? 0.5 : 0.5
    }

    var body: some View {
        if scheme == .dark {
            gradient
                .colorEffect(ShaderLibrary.parameterizedNoise(
                    .float(noiseIntensity),
                    .float(noiseScale),
                    .float(noiseFrequency)
                ))
                .ignoresSafeArea()
        } else {
            gradient
                .ignoresSafeArea()
        }
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Color.indigo.opacity(opacity), baseColor],
            startPoint: .top,
            endPoint: endPoint
        )
    }

    private var baseColor: Color {
#if os(iOS)
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
        })
#else
        scheme == .dark ? .black : .white
#endif
    }
}
