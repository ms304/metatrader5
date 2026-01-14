#property copyright "Copyright 2024"
#property version   "1.20"
#property strict

//--- INPUTS
input int    StartHour            = 0;
input int    EndHour              = 8;
input double AlertThresholdPercent = 0.05; // Proximité en % (ex: 0.05% du prix)

//--- STRUCTURE
struct SymbolState { 
    string name; 
    bool hAlert; 
    bool lAlert; 
};
SymbolState m_list[];

int OnInit() { 
    EventSetTimer(30); 
    return(INIT_SUCCEEDED); 
}

void OnDeinit(const int r) { 
    EventKillTimer(); 
}

void OnTimer() {
    int total = SymbolsTotal(true);
    if(ArraySize(m_list) != total) ArrayResize(m_list, total);

    for(int i=0; i<total; i++) {
        string sym = SymbolName(i, true);
        CheckAlerts(sym, i);
    }
}

void CheckAlerts(string sym, int idx) {
    MqlDateTime dt; 
    TimeCurrent(dt);
    
    string dP = IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day);
    datetime sT = StringToTime(dP + " " + (StartHour < 10 ? "0" : "") + IntegerToString(StartHour) + ":00");
    datetime eT = StringToTime(dP + " " + (EndHour < 10 ? "0" : "") + IntegerToString(EndHour) + ":00");

    int sB = iBarShift(sym, _Period, sT, false);
    int eB = iBarShift(sym, _Period, eT, false);
    if(iTime(sym, _Period, sB) < sT) sB--;
    int count = sB - eB;

    if(count > 0) {
        double h = iHigh(sym, _Period, iHighest(sym, _Period, MODE_HIGH, count, eB + 1));
        double l = iLow(sym, _Period, iLowest(sym, _Period, MODE_LOW, count, eB + 1));
        
        double bid = SymbolInfoDouble(sym, SYMBOL_BID);
        double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
        int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

        if(m_list[idx].name != sym) { 
            m_list[idx].name = sym; 
            m_list[idx].hAlert = false; 
            m_list[idx].lAlert = false; 
        }

        // --- CALCUL DE LA DISTANCE EN POURCENTAGE ---
        double distanceHighPct = ((h - bid) / h) * 100;
        double distanceLowPct  = ((ask - l) / l) * 100;

        // --- ALERTE HIGH ---
        // On alerte si la distance est positive et inférieure au seuil
        if(distanceHighPct > 0 && distanceHighPct <= AlertThresholdPercent && !m_list[idx].hAlert) {
            string msg = "⚠️ PROXIMITÉ HIGH [" + DoubleToString(distanceHighPct, 3) + "%] (" + sym + ")\n" +
                         "Prix Actuel: " + DoubleToString(bid, digits) + "\n" +
                         "Niveau Asian: " + DoubleToString(h, digits);
            Alert(msg);
            SendNotification(msg);
            m_list[idx].hAlert = true;
        }

        // --- ALERTE LOW ---
        if(distanceLowPct > 0 && distanceLowPct <= AlertThresholdPercent && !m_list[idx].lAlert) {
            string msg = "⚠️ PROXIMITÉ LOW [" + DoubleToString(distanceLowPct, 3) + "%] (" + sym + ")\n" +
                         "Prix Actuel: " + DoubleToString(ask, digits) + "\n" +
                         "Niveau Asian: " + DoubleToString(l, digits);
            Alert(msg);
            SendNotification(msg);
            m_list[idx].lAlert = true;
        }

        // Reset à minuit
        if(dt.hour == 0 && dt.min == 0) { 
            m_list[idx].hAlert = false; 
            m_list[idx].lAlert = false; 
        }
    }
}
