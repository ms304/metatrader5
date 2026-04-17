//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN (RETRY 10 SECONDES SUR ERREUR 503)            |
//| AVEC TRADING LONG ET SHORT - VERSION 5.07 CORRIGÉE               |
//+------------------------------------------------------------------+
#property version "5.07"
#property copyright "Copyright 2025, SMC EA"

#include <Trade/Trade.mqh>
CTrade trade;

// --- Paramètres d'entrée ---
input string API_KEY = "elle est belle elle est trop belle";
input int IntervalMin = 5;
input double LotSize = 0.01;           // Taille de la position
input double RiskPercent = 1.0;        // Risque en % du capital (0 = lot fixe)
input int Slippage = 30;               // Slippage en points
input int MaxSpread = 60;              // Spread maximum autorisé (en points)
input bool UseBreakeven = true;        // Activer le breakeven
input int BreakevenPips = 50;          // Points de profit pour passer en BE
input bool UseTrailingStop = true;     // Activer le trailing stop
input int TrailingStart = 30;          // Points de profit pour démarrer le trailing
input int TrailingStep = 15;           // Pas du trailing stop en points
input bool AllowPartialPattern = false; // Autoriser les patterns partiels
input bool DebugMode = true;            // Mode débogage (affiche tout)
input bool AllowLong = true;            // Autoriser les trades LONG
input bool AllowShort = true;           // Autoriser les trades SHORT

// --- Paramètres avancés ---
input int MaxEntryDistancePoints = 500; // Distance max entre prix actuel et entrée (en points)

// --- Variables globales ---
datetime nextCallTime = 0;
bool isFirstCall = true;
ulong magicNumber = 20250417;          // Numéro magique pour identifier les trades
bool webRequestWarningShown = false;    // Pour n'afficher l'avertissement qu'une fois

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
   string fileName = "Gemini_Logs_" + GetDateString() + ".txt";
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
   string fileName = "Gemini_Trades_" + GetDateString() + ".txt";
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
//| Calcul de la taille de lot dynamique                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskDistance)
  {
   if(RiskPercent <= 0 || riskDistance <= 0)
      return LotSize;

   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize == 0 || tickValue == 0)
      return LotSize;
      
   double lossForOneLot = (riskDistance / tickSize) * tickValue;
   if(lossForOneLot == 0)
      return LotSize;

   double lot = riskAmount / lossForOneLot;

   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0)
      lot = MathFloor(lot / lotStep) * lotStep;

   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;

   return NormalizeDouble(lot, 2);
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

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
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
      if(DebugMode) Print("Position déjà ouverte, pas de nouvelle entrée");
      return false;
     }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   // Vérifier la distance par rapport à l'entrée suggérée
   double entryDistance = MathAbs(ask - entry) / point;
   if(entryDistance > MaxEntryDistancePoints)
     {
      Print("Prix actuel trop éloigné de l'entrée suggérée: ", entryDistance, " points > ", MaxEntryDistancePoints);
      return false;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(sl >= ask)
     {
      Print("ERREUR LONG: Le SL (", sl, ") doit être inférieur au prix d'achat actuel (", ask, ")");
      return false;
     }
   if(tp <= ask && tp > 0)
     {
      Print("ERREUR LONG: Le TP (", tp, ") doit être supérieur au prix d'achat actuel (", ask, ")");
      return false;
     }

   if(stopLevel > 0)
     {
      if((ask - sl) < (stopLevel * point))
        {
         Print("ERREUR LONG: SL trop proche du prix. Distance requise: ", stopLevel * point);
         return false;
        }
      if(tp > 0 && (tp - ask) < (stopLevel * point))
        {
         Print("ERREUR LONG: TP trop proche du prix. Distance requise: ", stopLevel * point);
         return false;
        }
     }

   double riskDistance = MathAbs(ask - sl);
   double lot = CalculateLotSize(riskDistance);

   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("=== TENTATIVE DE TRADE LONG ===");
   Print("Entrée suggérée IA: ", entry, " | Prix Execution Ask: ", ask);
   Print("SL normalisé: ", sl, " | TP normalisé: ", tp, " | Lot: ", lot);

   if(trade.Buy(lot, _Symbol, ask, sl, tp, "Gemini SMC Long"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ Trade LONG exécuté! Ticket: ", ticket);
      LogTrade(StringFormat("LONG ENTRY: Prix=%.5f, SL=%.5f, TP=%.5f, Lot=%.2f, Ticket=%d", ask, sl, tp, lot, ticket));
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
      if(DebugMode) Print("Position déjà ouverte, pas de nouvelle entrée");
      return false;
     }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   double entryDistance = MathAbs(bid - entry) / point;
   if(entryDistance > MaxEntryDistancePoints)
     {
      Print("Prix actuel trop éloigné de l'entrée suggérée: ", entryDistance, " points > ", MaxEntryDistancePoints);
      return false;
     }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(sl <= bid && sl > 0)
     {
      Print("ERREUR SHORT: Le SL (", sl, ") doit être supérieur au prix de vente actuel (", bid, ")");
      return false;
     }
   if(tp >= bid && tp > 0)
     {
      Print("ERREUR SHORT: Le TP (", tp, ") doit être inférieur au prix de vente actuel (", bid, ")");
      return false;
     }

   if(stopLevel > 0)
     {
      if((sl - bid) < (stopLevel * point))
        {
         Print("ERREUR SHORT: SL trop proche du prix. Distance requise: ", stopLevel * point);
         return false;
        }
      if(tp > 0 && (bid - tp) < (stopLevel * point))
        {
         Print("ERREUR SHORT: TP trop proche du prix. Distance requise: ", stopLevel * point);
         return false;
        }
     }

   double riskDistance = MathAbs(bid - sl);
   double lot = CalculateLotSize(riskDistance);

   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(Slippage);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("=== TENTATIVE DE TRADE SHORT ===");
   Print("Entrée suggérée IA: ", entry, " | Prix Execution Bid: ", bid);
   Print("SL normalisé: ", sl, " | TP normalisé: ", tp, " | Lot: ", lot);

   if(trade.Sell(lot, _Symbol, bid, sl, tp, "Gemini SMC Short"))
     {
      ulong ticket = trade.ResultOrder();
      Print("✓ Trade SHORT exécuté! Ticket: ", ticket);
      LogTrade(StringFormat("SHORT ENTRY: Prix=%.5f, SL=%.5f, TP=%.5f, Lot=%.2f, Ticket=%d", bid, sl, tp, lot, ticket));
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
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magicNumber)
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
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;

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
            Print("SL mis à jour pour le ticket ", ticket, " -> ", newSL);
            LogTrade(StringFormat("SL UPDATED: Ticket=%d, Type=%s, Nouveau SL=%.5f", ticket, (type == POSITION_TYPE_BUY ? "BUY":"SELL"), newSL));
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Extraction améliorée des niveaux de trade                        |
//+------------------------------------------------------------------+
bool ExtractTradeLevels(string response, double &entry, double &sl, double &tp, int &direction)
  {
   entry = 0; sl = 0; tp = 0; direction = 0;
   string upperResponse = ToUpperCase(response);

   if(StringFind(upperResponse, "DECISION: LONG") >= 0) direction = 1;
   else if(StringFind(upperResponse, "DECISION: SHORT") >= 0) direction = -1;
   else return false;

   // Entry
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
         else if(StringLen(entryStr) > 0 && (ch == '\n' || ch == '\r')) break;
        }
      StringReplace(entryStr, ",", ".");
      entry = StringToDouble(entryStr);
     }

   // SL
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
         else if(StringLen(slStr) > 0 && (ch == '\n' || ch == '\r')) break;
        }
      StringReplace(slStr, ",", ".");
      sl = StringToDouble(slStr);
     }

   // TP
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
         else if(StringLen(tpStr) > 0 && (ch == '\n' || ch == '\r')) break;
        }
      StringReplace(tpStr, ",", ".");
      tp = StringToDouble(tpStr);
     }

   if(entry == 0 || sl == 0 || tp == 0)
     {
      if(DebugMode) Print("Échec extraction: entry=", entry, " sl=", sl, " tp=", tp);
      return false;
     }

   if(direction == 1 && sl < entry && tp > entry) return true;
   if(direction == -1 && sl > entry && tp < entry) return true;

   if(DebugMode) Print("Échec validation logique: direction=", direction);
   return false;
  }

//+------------------------------------------------------------------+
//| Fonctions Utilitaires                                            |
//+------------------------------------------------------------------+
string GetData(int count)
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, count, r) < count) return "";
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
   int candlesToFetch = isFirstCall ? 48 : 10;
   string data_str = GetData(candlesToFetch);
   if(data_str == "") { nextCallTime = TimeCurrent() + 10; return; }
   
   // Obtenir le prix actuel
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=" + API_KEY;

   string context = isFirstCall ? "4 hours of" : "last 10";

   string prompt =
      "You are an expert SMC/ICT trader. CURRENT PRICE OF XAUUSD IS: " + DoubleToString(currentPrice, digits) + ". " +
      "Analyze this chronological sequence of " + context + " XAUUSD M5 candles " +
      "provided as High(H), Low(L), and Close(C): " + data_str + ". " +
      "The current price is " + DoubleToString(currentPrice, digits) + ". " +
      "Look strictly for these two setups based on the CURRENT PRICE:\n\n" +
      "=== LONG SETUP ===\n" +
      "1. Creation of a clear Buy Side Liquidity (BSL) swing high ABOVE current price.\n" +
      "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price dropped below a low but rejected/closes higher).\n" +
      "3. Market structure shifting upwards to target the BSL high.\n" +
      "4. Entry should be near current price (within 50 points/pips).\n\n" +
      "=== SHORT SETUP ===\n" +
      "1. Creation of a clear Sell Side Liquidity (SSL) swing low BELOW current price.\n" +
      "2. A sweep of a previous Buy Side Liquidity (BSL) swing high (price rose above a high but rejected/closes lower).\n" +
      "3. Market structure shifting downwards to target the SSL low.\n" +
      "4. Entry should be near current price (within 50 points/pips).\n\n" +
      "If a LONG setup is confirmed with entry near current price, respond EXACTLY in this format:\n" +
      "DECISION: LONG\nENTRY: X.XX\nSL: X.XX\nTP: X.XX\nREASON: brief explanation\n\n" +
      "If a SHORT setup is confirmed with entry near current price, respond EXACTLY in this format:\n" +
      "DECISION: SHORT\nENTRY: X.XX\nSL: X.XX\nTP: X.XX\nREASON: brief explanation\n\n" +
      "If no setup is confirmed or entry is not near current price, respond EXACTLY:\n" +
      "DECISION: WAIT\nREASON: brief explanation\n\n" +
      "IMPORTANT: Entry price MUST be within 50 points of the current price " + DoubleToString(currentPrice, digits) + ". " +
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
         Print("IMPORTANT: Pour utiliser l'API Gemini, vous devez:");
         Print("1. Aller dans Outils -> Options -> Expert Advisors");
         Print("2. Cocher 'Autoriser les requêtes WebRequest'");
         Print("3. Ajouter 'https://generativelanguage.googleapis.com' dans la liste des URLs autorisées");
         Print("========================================================");
         webRequestWarningShown = true;
        }
      nextCallTime = TimeCurrent() + 60;
      return;
     }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   
   if(DebugMode)
     {
      Print("Taille de la réponse JSON: ", StringLen(out), " caractères");
     }
   
   string finalResponse = ExtractFullResponse(out);
   
   if(DebugMode)
     {
      Print("Taille du texte extrait: ", StringLen(finalResponse), " caractères");
     }
   
   LogResponse(finalResponse);
   
   Print("========================================");
   Print("Reponse Gemini recue a ", TimeToString(TimeCurrent()));
   Print("Prix actuel: ", DoubleToString(currentPrice, digits));
   if(DebugMode)
      Print("Debut de la reponse: ", StringSubstr(finalResponse, 0, 200), "...");
   Print("========================================");

   if(res == 503 || res == 429)
     {
      Print("Serveurs Gemini surcharges (Code ", res, "). Nouvel essai dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10;
      return; 
     }
   else if(res != 200)
     {
      Print("Erreur API Gemini fatale (Code ", res, "). Nouvel essai dans 1 minute.");
      nextCallTime = TimeCurrent() + 60;
      return; 
     }

   if(isFirstCall) 
     {
      Print("Contexte initial analyse par l'IA avec succes.");
      isFirstCall = false; 
     }
   
   double entry, sl, tp;
   int direction;
   
   if(ExtractTradeLevels(finalResponse, entry, sl, tp, direction))
     {
      // Vérification supplémentaire que l'entrée est proche du prix actuel
      double entryDistance = MathAbs(currentPrice - entry);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
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
         Print("Entrée trop éloignée: ", entryDistancePoints, " points (max: ", MaxEntryDistancePoints, ")");
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
   Print("EA GEMINI SMC PATTERN démarré - Version 5.07");
   Print("Symbole: ", _Symbol);
   Print("Magic Number: ", magicNumber);
   Print("Spread max: ", MaxSpread);
   Print("Distance max entrée: ", MaxEntryDistancePoints, " points");
   
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("ERREUR: Veuillez autoriser le trading automatique");
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
   Print("EA GEMINI SMC PATTERN arrêté. Raison: ", reason);
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
