import Foundation

struct BatteryPrediction {
    let currentHealth: Int
    let cycleCount: Int
    let predictedHealthOneYear: Int
    let predictedHealthTwoYears: Int
    let condition: String
    let advice: String
}

class BatteryHealthPredictor {
    static func predict(cycleCount: Int, maxCapacityPercent: Int, condition: String) -> BatteryPrediction {
        // Standard lithium ion degradation approximation:
        // ~1% drop every 50 cycles under typical conditions.
        // If BCLM is enabled (e.g. charging limited to 80%), degradation is estimated to be ~40% slower!
        let bclmLimit = UserDefaults.standard.integer(forKey: "bclm_limit")
        let isLimitEnabled = bclmLimit > 0 && bclmLimit < 100
        
        let degradationPer50Cycles: Double = isLimitEnabled ? 0.6 : 1.0 // 40% slower if charging limited
        
        // Let's assume average usage of 150 cycles per year.
        let cyclesInOneYear = 150
        let cyclesInTwoYears = 300
        
        let healthDropOneYear = Double(cyclesInOneYear) / 50.0 * degradationPer50Cycles
        let healthDropTwoYears = Double(cyclesInTwoYears) / 50.0 * degradationPer50Cycles
        
        let predictedHealthOne = max(50, maxCapacityPercent - Int(healthDropOneYear))
        let predictedHealthTwo = max(50, maxCapacityPercent - Int(healthDropTwoYears))
        
        var advice = ""
        if maxCapacityPercent <= 80 {
            advice = "Your battery health has dropped below 80%. We recommend servicing the battery soon."
        } else if isLimitEnabled {
            advice = "Smart Charge Limit is active (limited to \(bclmLimit)%). Battery aging is reduced by ~40%."
        } else {
            advice = "We recommend enabling the Smart Charge Limit (e.g. 80%) in Settings to slow down battery aging."
        }
        
        return BatteryPrediction(
            currentHealth: maxCapacityPercent,
            cycleCount: cycleCount,
            predictedHealthOneYear: predictedHealthOne,
            predictedHealthTwoYears: predictedHealthTwo,
            condition: condition,
            advice: advice
        )
    }
}
