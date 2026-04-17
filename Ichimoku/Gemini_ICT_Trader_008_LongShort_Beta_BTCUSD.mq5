//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN - BITCOIN EDITION (VERSION 5.09)              |
//| AVEC TRADING LONG ET SHORT - OPTIMISÉ POUR BTCUSD                |
//+------------------------------------------------------------------+
#property version "5.09"
#property copyright "Copyright 2025, SMC EA - Bitcoin Edition"

#include <Trade/Trade.mqh>
CTrade trade;

// --- Paramètres d'entrée ---
input string API_KEY = "Dans sa ... J'fais du paddle";

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
input int MaxEntryDistancePoints = 1500; // Distance max entre prix actuel et entrée (points)
input double MinRRRatio = 2.0;           // Ratio risque/récompense minimum (1:2 pour BTC)
input int MaxSLPoints = 1200;            // Stop Loss maximum en points
input int MinSLPoints = 200;             // Stop Loss minimum en points
input double MaxRiskPerTrade = 1.0;      // Risque maximum par trade (% du capital)

// --- Variables globales ---
datetime nextCallTime = 0;
bool isFirstCall = true;
ulong magicNumber = 20250418;            // Numéro magique différent pour BTC
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
   // Vérifier si le symbole existe
   if(SymbolSelect(CryptoSymbol, true))
     {
      Print("✅ Symbole trouvé: ", CryptoSymbol);
      return true;
     }
   
   // Liste des symboles Bitcoin alternatifs
   string alternatives[] = {"BTCUSDT", "BITCOIN", "BTCUSD", "BTCUSDT", "XBTUSD"};
   
   for(int i = 0; i < ArraySize(alternatives); i++)
     {
      if(SymbolSelect(alternatives[i], true))
        {
         Print("⚠️ Symbole ", CryptoSymbol, " non trouvé. Utilisation de ", alternatives[i]);
         //CryptoSymbol = alternatives[i];
         return true;
        }
     }
   
   Print("❌ Aucun symbole Bitcoin trouvé ! Vérifiez le Market Watch.");
   return false;
  }

//+------------------------------------------------------------------+
//| VÉRIFICATION DU RATIO RISQUE/RÉCOMPENSE                          |
//+------------------------------------------------------------------+
bool ValidateRiskReward(double entry, double sl, double tp, int direction)
  {
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   double slDistance = 0, tpDistance = 0;
   
   if(direction == 1) // LONG
     {
      slDistance = (entry - sl) / point;
      tpDistance = (tp - entry) / point;
     }
   else // SHORT
     {
      slDistance = (sl - entry) / point;
      tpDistance = (entry - tp) / point;
     }
   
   Print("=== VALIDATION RISQUE/RÉCOMPENSE (BTC) ===");
   Print("Distance SL: ", DoubleToString(slDistance, 1), " points");
   Print("Distance TP: ", DoubleToString(tpDistance, 1), " points");
   
   if(slDistance < MinSLPoints)
     {
      Print("❌ SL TROP SERRÉ pour BTC: ", slDistance, " points (minimum: ", MinSLPoints, ")");
      LogTrade(StringFormat("REJECTED: SL too tight for BTC (%.1f pts < %d)", slDistance, MinSLPoints));
      return false;
     }
   
   if(slDistance > MaxSLPoints)
     {
      Print("❌ SL TROP LARGE pour BTC: ", slDistance, " points (maximum: ", MaxSLPoints, ")");
      LogTrade(StringFormat("REJECTED: SL too wide for BTC (%.1f pts > %d)", slDistance, MaxSLPoints));
      return false;
     }
   
   double rrRatio = tpDistance / slDistance;
   Print("Ratio Risque/Récompense: ", DoubleToString(rrRatio, 2));
   
   if(rrRatio < MinRRRatio)
     {
      Print("❌ MAUVAIS RATIO RR pour BTC: ", DoubleToString(rrRatio, 2), " (minimum requis: ", MinRRRatio, ")");
      LogTrade(StringFormat("REJECTED: Poor RR ratio for BTC (%.2f < %.1f)", rrRatio, MinRRRatio));
      return false;
     }
   
   Print("✅ RR VALIDE pour BTC: ", DoubleToString(rrRatio, 2));
   return true;
  }

//+------------------------------------------------------------------+
//| Calcul de la taille de lot dynamique pour Bitcoin                |
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
      Print("⚠️ Risque réduit de ", RiskPercent, "% à ", MaxRiskPerTrade, "% pour BTC");
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

   return NormalizeDouble(lot, 3); // Bitcoin supporte 3 décimales parfois
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
      Print("Spread BTC trop élevé: ", currentSpread, " > ", MaxSpread);
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Exécution d'un trade LONG sur Bitcoin                            |
//+------------------------------------------------------------------+
bool ExecuteLongTrade(double entry, double sl, double tp)
  {
   if(!CanTrade() || !AllowLong) return false;

   if(GetLastPositionTicket() > 0)
     {
      if(DebugMode) Print("Position déjà ouverte sur BTC");
      return false;
     }

   double ask = SymbolInfoDouble(CryptoSymbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(CryptoSymbol, SYMBOL_TRADE_STOPS_LEVEL);

   double entryDistance = MathAbs(ask - entry) / point;
   if(entryDistance > MaxEntryDistancePoints)
     {
      Print("Prix BTC trop éloigné de l'entrée: ", entryDistance, " points > ", MaxEntryDistancePoints);
      return false;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(!ValidateRiskReward(entry, sl, tp, 1))
     {
      Print("❌ Trade LONG BTC refusé - Mauvais ratio RR");
      return false;
     }

   if(sl >= ask)
     {
      Print("ERREUR LONG BTC: SL (", sl, ") doit être < prix actuel (", ask, ")");
      return false;
     }
   if(tp <= ask && tp > 0)
     {
      Print("ERREUR LONG BTC: TP (", tp, ") doit être > prix actuel (", ask, ")");
      return false;
     }

   if(stopLevel > 0)
     {
      if((ask - sl) < (stopLevel * point))
        {
         Print("ERREUR LONG BTC: SL trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
      if(tp > 0 && (tp - ask) < (stopLevel * point))
        {
         Print("ERREUR LONG BTC: TP trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
     }

   double riskDistance = MathAbs(ask - sl);
   double lot = CalculateLotSize(riskDistance);

   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("=== TENTATIVE DE TRADE LONG BTC ===");
   Print("Entrée IA: ", entry, " | Ask: ", ask);
   Print("SL: ", sl, " | TP: ", tp, " | Lot: ", lot);

   if(trade.Buy(lot, CryptoSymbol, ask, sl, tp, "Gemini SMC Long BTC"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ Trade LONG BTC exécuté! Ticket: ", ticket);
      LogTrade(StringFormat("LONG BTC: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.3f, RR=%.2f", ask, sl, tp, lot, (tp-entry)/(entry-sl)));
      return true;
     }
   else
     {
      Print("✗ Erreur LONG BTC: ", GetLastError());
      return false;
     }
  }

//+------------------------------------------------------------------+
//| Exécution d'un trade SHORT sur Bitcoin                           |
//+------------------------------------------------------------------+
bool ExecuteShortTrade(double entry, double sl, double tp)
  {
   if(!CanTrade() || !AllowShort) return false;

   if(GetLastPositionTicket() > 0)
     {
      if(DebugMode) Print("Position déjà ouverte sur BTC");
      return false;
     }

   double bid = SymbolInfoDouble(CryptoSymbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(CryptoSymbol, SYMBOL_TRADE_STOPS_LEVEL);

   double entryDistance = MathAbs(bid - entry) / point;
   if(entryDistance > MaxEntryDistancePoints)
     {
      Print("Prix BTC trop éloigné de l'entrée: ", entryDistance, " points > ", MaxEntryDistancePoints);
      return false;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(!ValidateRiskReward(entry, sl, tp, -1))
     {
      Print("❌ Trade SHORT BTC refusé - Mauvais ratio RR");
      return false;
     }

   if(sl <= bid && sl > 0)
     {
      Print("ERREUR SHORT BTC: SL (", sl, ") doit être > prix actuel (", bid, ")");
      return false;
     }
   if(tp >= bid && tp > 0)
     {
      Print("ERREUR SHORT BTC: TP (", tp, ") doit être < prix actuel (", bid, ")");
      return false;
     }

   if(stopLevel > 0)
     {
      if((sl - bid) < (stopLevel * point))
        {
         Print("ERREUR SHORT BTC: SL trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
      if(tp > 0 && (bid - tp) < (stopLevel * point))
        {
         Print("ERREUR SHORT BTC: TP trop proche. Distance requise: ", stopLevel * point);
         return false;
        }
     }

   double riskDistance = MathAbs(bid - sl);
   double lot = CalculateLotSize(riskDistance);

   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("=== TENTATIVE DE TRADE SHORT BTC ===");
   Print("Entrée IA: ", entry, " | Bid: ", bid);
   Print("SL: ", sl, " | TP: ", tp, " | Lot: ", lot);

   if(trade.Sell(lot, CryptoSymbol, bid, sl, tp, "Gemini SMC Short BTC"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ Trade SHORT BTC exécuté! Ticket: ", ticket);
      LogTrade(StringFormat("SHORT BTC: Prix=%.2f, SL=%.2f, TP=%.2f, Lot=%.3f, RR=%.2f", bid, sl, tp, lot, (entry-tp)/(sl-entry)));
      return true;
     }
   else
     {
      Print("✗ Erreur SHORT BTC: ", GetLastError());
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
//| Gestion Breakeven et Trailing pour Bitcoin                       |
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
            Print("SL BTC mis à jour pour ", ticket, " -> ", newSL);
            LogTrade(StringFormat("SL UPDATED BTC: Ticket=%d, Nouveau SL=%.2f", ticket, newSL));
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
//| Fonction principale CallGemini pour Bitcoin                      |
//+------------------------------------------------------------------+
void CallGemini()
  {
   int candlesToFetch = isFirstCall ? 48 : 10;
   string data_str = GetData(candlesToFetch);
   if(data_str == "") { nextCallTime = TimeCurrent() + 10; return; }
   
   double currentPrice = SymbolInfoDouble(CryptoSymbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(CryptoSymbol, SYMBOL_DIGITS);
   
   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=" + API_KEY;
   string context = isFirstCall ? "4 hours of" : "last 10";

   string prompt =
      "You are an expert SMC/ICT trader for BITCOIN. CURRENT PRICE OF " + CryptoSymbol + " IS: " + DoubleToString(currentPrice, digits) + ". " +
      "Analyze this chronological sequence of " + context + " " + CryptoSymbol + " M5 candles " +
      "provided as High(H), Low(L), and Close(C): " + data_str + ". " +
      "The current price is " + DoubleToString(currentPrice, digits) + ". " +
      "Look strictly for these two setups based on the CURRENT PRICE:\n\n" +
      "=== LONG SETUP ===\n" +
      "1. Creation of a clear Buy Side Liquidity (BSL) swing high ABOVE current price.\n" +
      "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price dropped below a low but rejected/closes higher).\n" +
      "3. Market structure shifting upwards to target the BSL high.\n\n" +
      "=== SHORT SETUP ===\n" +
      "1. Creation of a clear Sell Side Liquidity (SSL) swing low BELOW current price.\n" +
      "2. A sweep of a previous Buy Side Liquidity (BSL) swing high (price rose above a high but rejected/closes lower).\n" +
      "3. Market structure shifting downwards to target the SSL low.\n\n" +
      "CRITICAL RISK RULES FOR BITCOIN (HIGH VOLATILITY):\n" +
      "- SL must be between 200 and 1200 points from entry\n" +
      "- TP must provide at least 2.0x reward vs risk (RR >= 2.0)\n" +
      "- Example GOOD SHORT: ENTRY 50000, SL 50200 (200pts risk), TP 49600 (400pts reward) -> RR = 2.0\n" +
      "- Example BAD SHORT: ENTRY 50000, SL 51000 (1000pts risk), TP 49800 (200pts reward) -> RR = 0.2 (REJECT)\n\n" +
      "If a LONG setup is confirmed with good RR, respond EXACTLY:\n" +
      "DECISION: LONG\nENTRY: X.XX\nSL: X.XX\nTP: X.XX\nREASON: brief explanation\n\n" +
      "If a SHORT setup is confirmed with good RR, respond EXACTLY:\n" +
      "DECISION: SHORT\nENTRY: X.XX\nSL: X.XX\nTP: X.XX\nREASON: brief explanation\n\n" +
      "If no setup is confirmed, respond EXACTLY:\n" +
      "DECISION: WAIT\nREASON: brief explanation\n\n" +
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
   Print("Prix BTC actuel: ", DoubleToString(currentPrice, digits));
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
      double point = SymbolInfoDouble(CryptoSymbol, SYMBOL_POINT);
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
     }
   
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochain analyse BTC dans ", IntervalMin, " minutes.");
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("========================================");
   Print("GEMINI SMC BTC EDITION v5.09");
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
   Print("Risque/trade: ", RiskPercent, "% (max ", MaxRiskPerTrade, "%)");
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("ERREUR: Autorisez le trading automatique");
      return INIT_FAILED;
     }
   
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   
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
   
   if(TimeCurrent() >= nextCallTime)
     {
      CallGemini();
     }
  }
//+------------------------------------------------------------------+
