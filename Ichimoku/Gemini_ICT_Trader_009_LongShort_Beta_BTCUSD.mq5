//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN - BITCOIN EDITION (VERSION 5.11)              |
//| AVEC TRADING LONG ET SHORT - ATTENTE CLÔTURE BOUGIE              |
//| OPTIMISÉ POUR COMMISSIONS ET SL MINIMUM                          |
//+------------------------------------------------------------------+
#property version "5.11"
#property copyright "Copyright 2025, SMC EA - Bitcoin Edition"

#include <Trade/Trade.mqh>
CTrade trade;

// --- Paramètres d'entrée ---
input string API_KEY = "Golden Bitcoin Expert Advisor PRO";
input string CryptoSymbol = "BTCUSD";    // Symbole Bitcoin (BTCUSD, BTCUSDT, BITCOIN)
input int IntervalMin = 5;               // Intervalle d'analyse (minutes)
input double LotSize = 0.01;             // Taille de la position (0.01 BTC)
input double RiskPercent = 0.5;          // Risque en % du capital (REDUIT pour BTC)
input int Slippage = 50;                 // Slippage en points (plus élevé pour BTC)
input int MaxSpread = 200;               // Spread maximum autorisé (plus large pour BTC)
input bool UseBreakeven = true;          // Activer le breakeven
input int BreakevenPips = 400;           // Points de profit pour passer en BE
input bool UseTrailingStop = true;       // Activer le trailing stop
input int TrailingStart = 300;           // Points de profit pour démarrer le trailing
input int TrailingStep = 150;            // Pas du trailing stop en points
input bool AllowPartialPattern = false;  // Autoriser les patterns partiels
input bool DebugMode = true;             // Mode débogage (affiche tout)
input bool AllowLong = true;             // Autoriser les trades LONG
input bool AllowShort = true;            // Autoriser les trades SHORT

// --- Paramètres avancés Bitcoin ---
input int MaxEntryDistancePoints = 500;   // 500 dollars max d'écart
input double MinRRRatio = 2.5;            // RR minimum 1:2.5 (compense commissions)
input int MaxSLPoints = 1200;             // SL max 1200 dollars
input int MinSLPoints = 100;              // SL min 100 dollars (était 200)
input double MaxRiskPerTrade = 1.0;       // Risque maximum par trade (% du capital)

// --- Paramètres commissions ---
input double CommissionPerLot = 0.40;     // Commission aller-retour par lot (ex: 0.40$ pour 0.01 BTC)
input double MinNetProfitDollars = 0.50;  // Profit net minimum en dollars après commissions

// --- Variables globales ---
datetime nextCallTime = 0;
datetime lastBarTime = 0;                // Temps de la dernière bougie analysée
bool isFirstCall = true;
ulong magicNumber = 20250418;            // Numéro magique pour BTC
bool webRequestWarningShown = false;

//+------------------------------------------------------------------+
//| Fonction pour convertir en majuscules                            |
//+------------------------------------------------------------------+
string ToUpperCase(string text)
  {
   string result = "";
   for(int i = 0; i < StringLen(text); i++)
     {
      ushort ch = StringGetCharacter(text, i);
      if(ch >= 'a' && ch <= 'z')
         ch -= 32;
      result += CharToString((char)ch);
     }
   return result;
  }

//+------------------------------------------------------------------+
//| Fonction pour obtenir la date formatée YYYYMMDD                  |
//+------------------------------------------------------------------+
string GetDateString()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   return IntegerToString(dt.year) +
          IntegerToString(dt.mon, 2, '0') +
          IntegerToString(dt.day, 2, '0');
  }

//+------------------------------------------------------------------+
//| Fonction pour formater la date et l'heure                        |
//+------------------------------------------------------------------+
string GetDateTimeString()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   return IntegerToString(dt.year) + "-" +
          IntegerToString(dt.mon, 2, '0') + "-" +
          IntegerToString(dt.day, 2, '0') + " " +
          IntegerToString(dt.hour, 2, '0') + ":" +
          IntegerToString(dt.min, 2, '0') + ":" +
          IntegerToString(dt.sec, 2, '0');
  }

//+------------------------------------------------------------------+
//| Fonction pour loguer la réponse COMPLETE dans un fichier texte   |
//+------------------------------------------------------------------+
void LogResponse(string response)
  {
   string fileName = "Gemini_Logs_BTC_" + GetDateString() + ".txt";
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   if(fileHandle != INVALID_HANDLE)
     {
      FileSeek(fileHandle, 0, SEEK_END);
      string separator = "\r\n================================================================================\r\n";
      string header = "[" + GetDateTimeString() + "]\r\n";
      FileWriteString(fileHandle, separator);
      FileWriteString(fileHandle, header);
      FileWriteString(fileHandle, response);
      FileWriteString(fileHandle, "\r\n");
      FileClose(fileHandle);
     }
  }

//+------------------------------------------------------------------+
//| Fonction pour loguer les trades                                  |
//+------------------------------------------------------------------+
void LogTrade(string message)
  {
   string fileName = "Gemini_Trades_BTC_" + GetDateString() + ".txt";
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   if(fileHandle != INVALID_HANDLE)
     {
      FileSeek(fileHandle, 0, SEEK_END);
      string logEntry = "[" + GetDateTimeString() + "] " + message + "\r\n";
      FileWriteString(fileHandle, logEntry);
      FileClose(fileHandle);
     }
  }

//+------------------------------------------------------------------+
//| Vérification du symbole Bitcoin                                  |
//+------------------------------------------------------------------+
bool CheckCryptoSymbol()
  {
   if(SymbolSelect(CryptoSymbol, true))
     {
      Print("✅ Symbole trouvé: ", CryptoSymbol);
      return true;
     }
   
   string alternatives[] = {"BTCUSDT", "BITCOIN", "BTCUSD", "XBTUSD"};
   
   for(int i = 0; i < ArraySize(alternatives); i++)
     {
      if(SymbolSelect(alternatives[i], true))
        {
         Print("⚠️ Symbole ", CryptoSymbol, " non trouvé. Utilisation de ", alternatives[i]);
         return true;
        }
     }
   
   Print("❌ Aucun symbole Bitcoin trouvé !");
   return false;
  }

//+------------------------------------------------------------------+
//| Vérifier si une nouvelle bougie est complète                     |
//+------------------------------------------------------------------+
bool IsNewBarComplete()
  {
   datetime lastBarTimeComplete = iTime(CryptoSymbol, PERIOD_M5, 0);
   
   if(lastBarTime != lastBarTimeComplete)
     {
      lastBarTime = lastBarTimeComplete;
      return true;
     }
   
   return false;
  }

//+------------------------------------------------------------------+
//| VÉRIFICATION DU RATIO RISQUE/RÉCOMPENSE AVEC COMMISSIONS        |
//+------------------------------------------------------------------+
bool ValidateRiskReward(double entry, double sl, double tp, int direction, double lot)
  {
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(CryptoSymbol, SYMBOL_TRADE_TICK_VALUE);
   double slDistance = 0, tpDistance = 0;
   
   if(direction == 1)
     {
      slDistance = (entry - sl) / point;
      tpDistance = (tp - entry) / point;
     }
   else
     {
      slDistance = (sl - entry) / point;
      tpDistance = (entry - tp) / point;
     }
   
   Print("=== VALIDATION RISQUE/RÉCOMPENSE (BTC) ===");
   Print("Distance SL: ", DoubleToString(slDistance, 1), " points");
   Print("Distance TP: ", DoubleToString(tpDistance, 1), " points");
   
   if(slDistance < MinSLPoints)
     {
      Print("❌ SL TROP SERRÉ: ", slDistance, " points (min: ", MinSLPoints, ")");
      LogTrade(StringFormat("REJECTED: SL too tight (%.1f pts < %d)", slDistance, MinSLPoints));
      return false;
     }
   
   if(slDistance > MaxSLPoints)
     {
      Print("❌ SL TROP LARGE: ", slDistance, " points (max: ", MaxSLPoints, ")");
      LogTrade(StringFormat("REJECTED: SL too wide (%.1f pts > %d)", slDistance, MaxSLPoints));
      return false;
     }
   
   double rrRatio = tpDistance / slDistance;
   Print("Ratio Risque/Récompense brut: ", DoubleToString(rrRatio, 2));
   
   if(rrRatio < MinRRRatio)
     {
      Print("❌ MAUVAIS RATIO RR: ", DoubleToString(rrRatio, 2), " (min: ", MinRRRatio, ")");
      LogTrade(StringFormat("REJECTED: Poor RR ratio (%.2f < %.1f)", rrRatio, MinRRRatio));
      return false;
     }
   
   // Calculer le profit net après commissions
   double grossProfit = tpDistance * point * tickValue * lot;
   double commission = CommissionPerLot * lot * 2; // Aller-retour
   double netProfit = grossProfit - commission;
   
   Print("Profit brut estimé: $", DoubleToString(grossProfit, 2));
   Print("Commission estimée: $", DoubleToString(commission, 2));
   Print("Profit net estimé: $", DoubleToString(netProfit, 2));
   
   if(netProfit < MinNetProfitDollars)
     {
      Print("❌ PROFIT NET TROP FAIBLE: $", DoubleToString(netProfit, 2), " (min: $", MinNetProfitDollars, ")");
      LogTrade(StringFormat("REJECTED: Net profit too low ($%.2f < $%.2f)", netProfit, MinNetProfitDollars));
      return false;
     }
   
   Print("✅ RR VALIDE: ", DoubleToString(rrRatio, 2));
   Print("✅ Profit net acceptable: $", DoubleToString(netProfit, 2));
   return true;
  }

//+------------------------------------------------------------------+
//| Calcul de la taille de lot dynamique                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskDistance)
  {
   if(RiskPercent <= 0 || riskDistance <= 0)
      return LotSize;

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   
   double maxRiskAmount = accountBalance * (MaxRiskPerTrade / 100.0);
   if(riskAmount > maxRiskAmount)
     {
      Print("⚠️ Risque réduit de ", RiskPercent, "% à ", MaxRiskPerTrade, "%");
      riskAmount = maxRiskAmount;
     }
   
   double tickSize = SymbolInfoDouble(CryptoSymbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(CryptoSymbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize == 0 || tickValue == 0)
      return LotSize;
      
   double lossForOneLot = (riskDistance / tickSize) * tickValue;
   if(lossForOneLot == 0)
      return LotSize;

   double lot = riskAmount / lossForOneLot;

   double lotStep = SymbolInfoDouble(CryptoSymbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;

   double lotMin = SymbolInfoDouble(CryptoSymbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(CryptoSymbol, SYMBOL_VOLUME_MAX);

   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;

   return NormalizeDouble(lot, 3);
  }

//+------------------------------------------------------------------+
//| Vérification des conditions de trading                           |
//+------------------------------------------------------------------+
bool CanTrade()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("Trading automatique non autorisé");
      return false;
     }

   double bid = SymbolInfoDouble(CryptoSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(CryptoSymbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   int currentSpread = (int)MathRound((ask - bid) / point);

   if(currentSpread > MaxSpread)
     {
      Print("Spread trop élevé: ", currentSpread, " > ", MaxSpread);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Exécution d'un trade LONG                                        |
//+------------------------------------------------------------------+
bool ExecuteLongTrade(double entry, double sl, double tp)
  {
   if(!CanTrade() || !AllowLong) return false;

   if(GetLastPositionTicket() > 0)
     {
      if(DebugMode) Print("Position déjà ouverte");
      return false;
     }

   double ask = SymbolInfoDouble(CryptoSymbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(CryptoSymbol, SYMBOL_TRADE_STOPS_LEVEL);

   double entryDistance = MathAbs(ask - entry) / point;
   if(entryDistance > MaxEntryDistancePoints)
     {
      Print("Prix trop éloigné de l'entrée: ", entryDistance, " points > ", MaxEntryDistancePoints);
      return false;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(sl >= ask)
     {
      Print("ERREUR LONG: SL (", sl, ") doit être < prix actuel (", ask, ")");
      return false;
     }
   if(tp <= ask && tp > 0)
     {
      Print("ERREUR LONG: TP (", tp, ") doit être > prix actuel (", ask, ")");
      return false;
     }

   if(stopLevel > 0)
     {
      if((ask - sl) < (stopLevel * point))
        {
         Print("ERREUR LONG: SL trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
      if(tp > 0 && (tp - ask) < (stopLevel * point))
        {
         Print("ERREUR LONG: TP trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
     }

   double riskDistance = MathAbs(ask - sl);
   double lot = CalculateLotSize(riskDistance);

   // Validation RR avec commissions
   if(!ValidateRiskReward(entry, sl, tp, 1, lot))
     {
      Print("❌ Trade LONG refusé - Mauvais ratio RR ou commissions trop élevées");
      return false;
     }

   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("=== TENTATIVE DE TRADE LONG BTC ===");
   Print("Entrée IA: ", entry, " | Ask: ", ask);
   Print("SL: ", sl, " | TP: ", tp, " | Lot: ", lot);

   if(trade.Buy(lot, CryptoSymbol, ask, sl, tp, "Gemini SMC Long BTC"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ Trade LONG exécuté! Ticket: ", ticket);
      LogTrade(StringFormat("LONG BTC: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.3f", ask, sl, tp, lot));
      return true;
     }
   else
     {
      Print("✗ Erreur LONG: ", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Exécution d'un trade SHORT                                       |
//+------------------------------------------------------------------+
bool ExecuteShortTrade(double entry, double sl, double tp)
  {
   if(!CanTrade() || !AllowShort) return false;

   if(GetLastPositionTicket() > 0)
     {
      if(DebugMode) Print("Position déjà ouverte");
      return false;
     }

   double bid = SymbolInfoDouble(CryptoSymbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(CryptoSymbol, SYMBOL_TRADE_STOPS_LEVEL);

   double entryDistance = MathAbs(bid - entry) / point;
   if(entryDistance > MaxEntryDistancePoints)
     {
      Print("Prix trop éloigné de l'entrée: ", entryDistance, " points > ", MaxEntryDistancePoints);
      return false;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(sl <= bid && sl > 0)
     {
      Print("ERREUR SHORT: SL (", sl, ") doit être > prix actuel (", bid, ")");
      return false;
     }
   if(tp >= bid && tp > 0)
     {
      Print("ERREUR SHORT: TP (", tp, ") doit être < prix actuel (", bid, ")");
      return false;
     }

   if(stopLevel > 0)
     {
      if((sl - bid) < (stopLevel * point))
        {
         Print("ERREUR SHORT: SL trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
      if(tp > 0 && (bid - tp) < (stopLevel * point))
        {
         Print("ERREUR SHORT: TP trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
     }

   double riskDistance = MathAbs(bid - sl);
   double lot = CalculateLotSize(riskDistance);

   // Validation RR avec commissions
   if(!ValidateRiskReward(entry, sl, tp, -1, lot))
     {
      Print("❌ Trade SHORT refusé - Mauvais ratio RR ou commissions trop élevées");
      return false;
     }

   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("=== TENTATIVE DE TRADE SHORT BTC ===");
   Print("Entrée IA: ", entry, " | Bid: ", bid);
   Print("SL: ", sl, " | TP: ", tp, " | Lot: ", lot);

   if(trade.Sell(lot, CryptoSymbol, bid, sl, tp, "Gemini SMC Short BTC"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ Trade SHORT exécuté! Ticket: ", ticket);
      LogTrade(StringFormat("SHORT BTC: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.3f", bid, sl, tp, lot));
      return true;
     }
   else
     {
      Print("✗ Erreur SHORT: ", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Récupère le ticket de la dernière position                       |
//+------------------------------------------------------------------+
ulong GetLastPositionTicket()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == CryptoSymbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
           {
            return ticket;
           }
        }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Gestion Breakeven et Trailing                                    |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   long stopLevel = SymbolInfoInteger(CryptoSymbol, SYMBOL_TRADE_STOPS_LEVEL);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != CryptoSymbol || PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);
      
      double profitPoints = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) / point : (openPrice - currentPrice) / point;

      bool slChanged = false;
      double newSL = sl;

      if(UseBreakeven && profitPoints >= BreakevenPips)
        {
         double beSL = openPrice + ((type == POSITION_TYPE_BUY) ? (2 * point) : (-2 * point));
         beSL = NormalizeDouble(beSL, digits);

         if(type == POSITION_TYPE_BUY && (sl == 0 || beSL > sl) && beSL <= currentPrice - (stopLevel * point))
           {
            newSL = beSL;
            slChanged = true;
           }
         else if(type == POSITION_TYPE_SELL && (sl == 0 || beSL < sl) && beSL >= currentPrice + (stopLevel * point))
           {
            newSL = beSL;
            slChanged = true;
           }
        }
        
      if(UseTrailingStop && profitPoints >= TrailingStart)
        {
         double trSL = 0;
         if(type == POSITION_TYPE_BUY)
           {
            trSL = currentPrice - (TrailingStep * point);
            trSL = NormalizeDouble(trSL, digits);
            if((sl == 0 || trSL > sl) && (!slChanged || trSL > newSL) && trSL <= currentPrice - (stopLevel * point))
              {
               newSL = trSL;
               slChanged = true;
              }
           }
         else
           {
            trSL = currentPrice + (TrailingStep * point);
            trSL = NormalizeDouble(trSL, digits);
            if((sl == 0 || trSL < sl) && (!slChanged || trSL < newSL) && trSL >= currentPrice + (stopLevel * point))
              {
               newSL = trSL;
               slChanged = true;
              }
           }
        }

      if(slChanged && MathAbs(newSL - sl) >= point)
        {
         trade.PositionModify(ticket, newSL, tp);
         if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
           {
            Print("SL mis à jour pour ", ticket, " -> ", newSL);
            LogTrade(StringFormat("SL UPDATED: Ticket=%d, Nouveau SL=%.2f", ticket, newSL));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Extraction des niveaux de trade                                  |
//+------------------------------------------------------------------+
bool ExtractTradeLevels(string response, double &entry, double &sl, double &tp, int &direction)
  {
   entry = 0; sl = 0; tp = 0; direction = 0;
   string upperResponse = ToUpperCase(response);

   if(StringFind(upperResponse, "DECISION: LONG") >= 0) direction = 1;
   else if(StringFind(upperResponse, "DECISION: SHORT") >= 0) direction = -1;
   else return false;

   int entryPos = StringFind(upperResponse, "ENTRY:");
   if(entryPos == -1) entryPos = StringFind(upperResponse, "ENTRÉE:");
   if(entryPos >= 0)
     {
      string entryStr = "";
      for(int i = entryPos + 6; i < entryPos + 30 && i < StringLen(response); i++)
        {
         ushort ch = StringGetCharacter(response, i);
         if((ch >= '0' && ch <= '9') || ch == '.' || ch == ',') 
            entryStr += CharToString((char)ch);
         else if(ch == ' ' && StringLen(entryStr) > 0) break;
        }
      StringReplace(entryStr, ",", ".");
      entry = StringToDouble(entryStr);
     }

   int slPos = StringFind(upperResponse, "SL:");
   if(slPos == -1) slPos = StringFind(upperResponse, "STOP LOSS:");
   if(slPos >= 0)
     {
      string slStr = "";
      int startOffset = (StringFind(upperResponse, "SL:") >= 0) ? 3 : 10;
      for(int i = slPos + startOffset; i < slPos + 30 && i < StringLen(response); i++)
        {
         ushort ch = StringGetCharacter(response, i);
         if((ch >= '0' && ch <= '9') || ch == '.' || ch == ',') 
            slStr += CharToString((char)ch);
         else if(ch == ' ' && StringLen(slStr) > 0) break;
        }
      StringReplace(slStr, ",", ".");
      sl = StringToDouble(slStr);
     }

   int tpPos = StringFind(upperResponse, "TP:");
   if(tpPos == -1) tpPos = StringFind(upperResponse, "TAKE PROFIT:");
   if(tpPos >= 0)
     {
      string tpStr = "";
      int startOffset = (StringFind(upperResponse, "TP:") >= 0) ? 3 : 12;
      for(int i = tpPos + startOffset; i < tpPos + 30 && i < StringLen(response); i++)
        {
         ushort ch = StringGetCharacter(response, i);
         if((ch >= '0' && ch <= '9') || ch == '.' || ch == ',') 
            tpStr += CharToString((char)ch);
         else if(ch == ' ' && StringLen(tpStr) > 0) break;
        }
      StringReplace(tpStr, ",", ".");
      tp = StringToDouble(tpStr);
     }

   if(entry == 0 || sl == 0 || tp == 0) return false;
   if(direction == 1 && sl < entry && tp > entry) return true;
   if(direction == -1 && sl > entry && tp < entry) return true;

   return false;
  }

//+------------------------------------------------------------------+
//| Fonctions Utilitaires                                            |
//+------------------------------------------------------------------+
string GetData(int count)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(CryptoSymbol, PERIOD_M5, 0, count, r) < count) return "";
   string s = "";
   for(int i = count - 1; i >= 0; i--)
     {
      s += "[H:" + DoubleToString(r[i].high, (int)Digits()) +
           " L:" + DoubleToString(r[i].low, (int)Digits()) +
           " C:" + DoubleToString(r[i].close, (int)Digits()) + "]";
      if(i > 0) s += ", ";
     }
   return s;
  }

string Clean(string s)
  {
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   return s;
  }

string ExtractFullResponse(string jsonResponse)
  {
   int startPos = StringFind(jsonResponse, "\"text\": \"");
   if(startPos == -1) return jsonResponse;
   startPos += 9;
   int endPos = startPos, len = StringLen(jsonResponse);
   bool inEscape = false;
   for(int i = startPos; i < len; i++)
     {
      ushort ch = StringGetCharacter(jsonResponse, i);
      if(inEscape) { inEscape = false; continue; }
      if(ch == '\\') { inEscape = true; continue; }
      if(ch == '"') { endPos = i; break; }
     }
   if(endPos == startPos) return jsonResponse;
   string result = StringSubstr(jsonResponse, startPos, endPos - startPos);
   StringReplace(result, "\\n", "\r\n");
   StringReplace(result, "\\r", "\r");
   StringReplace(result, "\\t", "\t");
   StringReplace(result, "\\\"", "\"");
   StringReplace(result, "\\\\", "\\");
   return result;
  }

//+------------------------------------------------------------------+
//| Fonction principale CallGemini                                   |
//+------------------------------------------------------------------+
void CallGemini()
  {
   int candlesToFetch = isFirstCall ? 48 : 2;
   string data_str = GetData(candlesToFetch);
   if(data_str == "") { nextCallTime = TimeCurrent() + 10; return; }
   
   double currentPrice = SymbolInfoDouble(CryptoSymbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   
   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=" + API_KEY;

   string context = isFirstCall ? "4 hours of" : "last 2 completed";

   double minSL_dollars = MinSLPoints * point;
   double maxSL_dollars = MaxSLPoints * point;
   
   string prompt =
      "You are an expert SMC/ICT trader for BITCOIN (BTCUSD). IMPORTANT: Bitcoin price is around " + DoubleToString(currentPrice, 0) + " dollars. " +
      "1 point = 1 dollar. Example: 50000 to 50001 = 1 point.\n\n" +
      "CURRENT PRICE OF BTCUSD IS: " + DoubleToString(currentPrice, 0) + " dollars.\n\n" +
      "Analyze this chronological sequence of " + context + " BTCUSD M5 candles " +
      "provided as High(H), Low(L), and Close(C): " + data_str + "\n\n" +
      "Look strictly for these two setups based on the CURRENT PRICE:\n\n" +
      "=== LONG SETUP ===\n" +
      "1. Creation of a clear Buy Side Liquidity (BSL) swing high ABOVE current price.\n" +
      "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price dropped below a low but rejected/closes higher).\n" +
      "3. Market structure shifting upwards to target the BSL high.\n\n" +
      "=== SHORT SETUP ===\n" +
      "1. Creation of a clear Sell Side Liquidity (SSL) swing low BELOW current price.\n" +
      "2. A sweep of a previous Buy Side Liquidity (BSL) swing high (price rose above a high but rejected/closes lower).\n" +
      "3. Market structure shifting downwards to target the SSL low.\n\n" +
      "CRITICAL RISK RULES FOR BITCOIN:\n" +
      "- SL MUST be between " + DoubleToString(minSL_dollars, 0) + " and " + DoubleToString(maxSL_dollars, 0) + " DOLLARS from entry\n" +
      "- NEVER use SL smaller than " + DoubleToString(minSL_dollars, 0) + " dollars! (Too small = commissions kill profit)\n" +
      "- TP must provide at least " + DoubleToString(MinRRRatio, 1) + "x reward vs risk (RR >= " + DoubleToString(MinRRRatio, 1) + ")\n" +
      "- Example GOOD SHORT: Current price 50000, ENTRY 50000, SL 50100 (100 dollars risk), TP 49750 (250 dollars reward) -> RR = 2.5\n" +
      "- Example BAD SHORT (TOO TIGHT): SL 50008 (8 dollars risk) - REJECTED! SL too small.\n\n" +
      "If a LONG setup is confirmed with good RR, respond EXACTLY:\n" +
      "DECISION: LONG\nENTRY: " + DoubleToString(currentPrice, 0) + "\nSL: X.XX\nTP: X.XX\nREASON: brief explanation\n\n" +
      "If a SHORT setup is confirmed with good RR, respond EXACTLY:\n" +
      "DECISION: SHORT\nENTRY: " + DoubleToString(currentPrice, 0) + "\nSL: X.XX\nTP: X.XX\nREASON: brief explanation\n\n" +
      "If no setup is confirmed, respond EXACTLY:\n" +
      "DECISION: WAIT\nREASON: brief explanation\n\n" +
      "IMPORTANT: SL and TP must be WHOLE NUMBERS (no decimals) like 50100, 49750.\n" +
      "SL must be at least " + DoubleToString(minSL_dollars, 0) + " dollars away from entry.\n" +
      "Do not add any other text outside this format.";

   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   string req_headers = "Content-Type: application/json\r\n", res_headers = "";
   char payload_in[], payload_out[];
   
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();
   int res = WebRequest("POST", url, req_headers, 30000, payload_in, payload_out, res_headers);

   if(res == -1)
     {
      Print("Erreur WebRequest: ", GetLastError());
      if(!webRequestWarningShown)
        {
         Print("========================================================");
         Print("Pour BTC, autorisez: https://generativelanguage.googleapis.com");
         Print("========================================================");
         webRequestWarningShown = true;
        }
      nextCallTime = TimeCurrent() + 60;
      return;
     }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   string finalResponse = ExtractFullResponse(out);
   
   LogResponse(finalResponse);
   
   Print("========================================");
   Print("BTC - Reponse Gemini a ", TimeToString(TimeCurrent()));
   Print("Prix BTC actuel: ", DoubleToString(currentPrice, 0));
   Print("========================================");

   if(res != 200)
     {
      Print("Erreur API (Code ", res, ")");
      nextCallTime = TimeCurrent() + 60;
      return; 
     }

   if(isFirstCall) 
     {
      Print("Analyse BTC initiale réussie");
      isFirstCall = false; 
     }
   
   double entry, sl, tp;
   int direction;
   
   if(ExtractTradeLevels(finalResponse, entry, sl, tp, direction))
     {
      double entryDistance = MathAbs(currentPrice - entry);
      double entryDistancePoints = entryDistance / point;
      
      if(entryDistancePoints <= MaxEntryDistancePoints)
        {
         if(direction == 1)
           {
            ExecuteLongTrade(entry, sl, tp);
           }
         else if(direction == -1)
           {
            ExecuteShortTrade(entry, sl, tp);
           }
        }
      else
        {
         Print("Entrée trop éloignée: ", entryDistancePoints, " points");
        }
     }
   else
     {
      if(DebugMode) Print("Aucun signal de trading valide");
     }
   
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochaine analyse dans ", IntervalMin, " minutes.");
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("========================================");
   Print("GEMINI SMC BTC EDITION v5.11");
   Print("✅ OPTIMISÉ POUR COMMISSIONS");
   Print("========================================");
   
   if(!CheckCryptoSymbol())
     {
      Print("❌ Erreur: Symbole Bitcoin non trouvé!");
      return INIT_FAILED;
     }
   
   Print("Symbole: ", CryptoSymbol);
   Print("Magic Number: ", magicNumber);
   Print("Spread max: ", MaxSpread);
   Print("RR minimum: ", MinRRRatio);
   Print("SL min: ", MinSLPoints, " | max: ", MaxSLPoints);
   Print("Commission par lot: $", CommissionPerLot);
   Print("Profit net minimum: $", MinNetProfitDollars);
   Print("Risque/trade: ", RiskPercent, "% (max ", MaxRiskPerTrade, "%)");
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("ERREUR: Autorisez le trading automatique");
      return INIT_FAILED;
     }
   
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   lastBarTime = iTime(CryptoSymbol, PERIOD_M5, 0);
   
   CallGemini();
   
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA BTC arrêté. Raison: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManagePositions();
   
   if(isFirstCall)
     {
      return;
     }
   
   if(IsNewBarComplete())
     {
      if(DebugMode) Print("🔔 Nouvelle bougie M5 complète - Analyse Gemini");
      CallGemini();
     }
  }
//+------------------------------------------------------------------+
