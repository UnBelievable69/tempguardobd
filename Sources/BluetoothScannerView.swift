import SwiftUI

struct BluetoothScannerView: View {

    @StateObject private var scanner = BluetoothScanner()
    @ObservedObject var settings: SettingsManager
    @Binding var isPresented: Bool
    var onDeviceSelected: (() -> Void)?

    var body: some View {
        NavigationView {
            Group {
                switch scanner.bluetoothState {
                case .poweredOn:
                    deviceListView
                case .poweredOff:
                    stateView(
                        icon: "antenna.radiowaves.left.and.right.slash",
                        title: "Bluetooth выключен",
                        message: "Включите Bluetooth в Настройках или Пункте управления."
                    )
                case .unauthorized:
                    stateView(
                        icon: "lock.shield",
                        title: "Нет доступа к Bluetooth",
                        message: "Разрешите доступ: Настройки - Конфиденциальность - Bluetooth."
                    )
                case .unsupported:
                    stateView(
                        icon: "exclamationmark.triangle",
                        title: "Bluetooth не поддерживается",
                        message: "Это устройство не поддерживает Bluetooth Low Energy."
                    )
                default:
                    ProgressView("Инициализация Bluetooth...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Выбор адаптера")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        scanner.stopScanning()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { scanner.startScanning() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(scanner.isScanning)
                }
            }
            .onAppear {
                if scanner.bluetoothState == .poweredOn {
                    scanner.startScanning()
                }
            }
            .onDisappear {
                scanner.stopScanning()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var deviceListView: some View {
        List {
            if scanner.isScanning {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Поиск устройств...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }
            }

            Section(
                header: Text("Найденные устройства (" + String(scanner.discoveredDevices.count) + ")")
            ) {
                if scanner.discoveredDevices.isEmpty && !scanner.isScanning {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("Устройства не найдены")
                                .foregroundColor(.secondary)
                            Text("Вставьте ELM327 в OBD2 разъём и включите зажигание. Нажмите ↻ для повтора.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                }

                ForEach(scanner.discoveredDevices) { device in
                    DeviceRowView(
                        device: device,
                        isSelected: settings.selectedDeviceUUID == device.id.uuidString
                    ) {
                        selectDevice(device)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func stateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectDevice(_ device: DiscoveredDevice) {
        scanner.stopScanning()
        settings.selectedDeviceName = device.name
        settings.selectedDeviceUUID = device.id.uuidString
        isPresented = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onDeviceSelected?()
        }
    }
}

struct DeviceRowView: View {
    let device: DiscoveredDevice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {

                Image(systemName: device.isLikelyOBD ? "car.fill" : "antenna.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundColor(device.isLikelyOBD ? .blue : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if device.isLikelyOBD {
                            Text("OBD")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }
                    Text(device.id.uuidString.prefix(13).uppercased())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                Spacer()

                VStack(spacing: 2) {
                    SignalBarsView(strength: device.signal)
                    Text(String(device.rssi) + " dBm")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct SignalBarsView: View {
    let strength: SignalStrength

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            bar(1)
            bar(2)
            bar(3)
            bar(4)
        }
        .frame(height: 22, alignment: .bottom)
    }

    private func bar(_ level: Int) -> some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(level <= strength.bars ? strength.color : Color(.systemGray4))
            .frame(width: 4, height: CGFloat(level * 4 + 4))
    }
}
