//
//  SettingsControls.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import SwiftUI
import VisualEngine

struct SettingsControls: View {
    @Bindable var settings: VisualSettingsViewModel
    let display: DisplayViewModel
    let palette: Palette

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("Style", selection: $settings.settings.style) {
                    ForEach(FlowStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                PaletteStrip(palette: palette)

                DisplayPicker(viewModel: display)
            }

            HStack(spacing: 16) {
                ParameterSlider(title: "Speed", value: $settings.settings.speed, range: 0.02...0.8)
                ParameterSlider(title: "Size", value: $settings.settings.scale, range: 0.6...4)
                ParameterSlider(title: "Warp", value: $settings.settings.warp, range: 0...6)
                ParameterSlider(title: "Resolution", value: $settings.settings.renderScale, range: 0.15...1)
                GPUReadout(viewModel: settings)
            }
        }
        .controlSize(.small)
    }
}

private struct DisplayPicker: View {
    @Bindable var viewModel: DisplayViewModel

    var body: some View {
        switch viewModel.availability {
        case .mirroring:
            Label(
                "The TV is mirroring this display. To send it only the visual, choose Use As Extended Display in Control Center › Screen Mirroring.",
                systemImage: "tv"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 340, alignment: .leading)
        case .noExternalDisplays:
            Label("Connect a TV via HDMI or AirPlay", systemImage: "tv")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("For AirPlay, use Control Center › Screen Mirroring, choose the TV, and select Use As Extended Display.")
        case .available(let displays):
            Picker("Display", selection: $viewModel.selectedDisplayID) {
                Text("This Mac").tag(CGDirectDisplayID?.none)
                ForEach(displays) { display in
                    Text(display.name).tag(CGDirectDisplayID?.some(display.id))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

private struct ParameterSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            Slider(value: $value, in: range)
                .labelsHidden()
        }
    }
}

private struct PaletteStrip: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(palette.colors.indices, id: \.self) { index in
                palette.colors[index].color
            }
        }
        .frame(width: 110, height: 18)
        .clipShape(.rect(cornerRadius: 5))
        .accessibilityHidden(true)
    }
}

private struct GPUReadout: View {
    let viewModel: VisualSettingsViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(alignment: .trailing, spacing: 2) {
                Text("GPU")
                    .font(.caption2)
                Text("\(viewModel.gpuMilliseconds, format: .number.precision(.fractionLength(1))) ms")
                    .font(.caption.monospacedDigit())
            }
        }
        .frame(width: 58, alignment: .trailing)
    }
}
