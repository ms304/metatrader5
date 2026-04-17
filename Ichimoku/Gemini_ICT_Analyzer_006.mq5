//+------------------------------------------------------------------+
//| GEMINI SMC PATTERN (RETRY 10 SECONDES SUR ERREUR 503)            |
//+------------------------------------------------------------------+
#property version "4.07"

input string API_KEY = "Sainte Marie Saint Denis La Possession Saint Joseph";

input int IntervalMin = 5;

// Remplacement de lastTime par nextCallTime pour un chronometre dynamique
datetime nextCallTime = 0; 
bool isFirstCall = true;

//+------------------------------------------------------------------+
//| Fonction pour obtenir la date formatée YYYYMMDD                   |
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
//| Fonction pour loguer la réponse dans un fichier horodaté         |
//+------------------------------------------------------------------+
void LogResponse(string response)
{
   string fileName = "Gemini_Logs_" + GetDateString() + ".txt";
   
   // En MT5, on ouvre en lecture/écriture et on se place à la fin
   int fileHandle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT);
   
   if(fileHandle != INVALID_HANDLE)
   {
      // Se placer à la fin du fichier pour ajouter
      FileSeek(fileHandle, 0, SEEK_END);
      
      MqlDateTime dt;
      TimeCurrent(dt);
      string logEntry = StringFormat("%04d.%02d.%02d %02d:%02d:%02d - %s\r\n", 
                                      dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, response);
      
      FileWriteString(fileHandle, logEntry);
      FileClose(fileHandle);
   }
   else
   {
      // Si le fichier n'existe pas, on le crée
      fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT);
      if(fileHandle != INVALID_HANDLE)
      {
         MqlDateTime dt;
         TimeCurrent(dt);
         string logEntry = StringFormat("%04d.%02d.%02d %02d:%02d:%02d - %s\r\n", 
                                         dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, response);
         FileWriteString(fileHandle, logEntry);
         FileClose(fileHandle);
      }
      else
      {
         Print("Erreur lors de l'ouverture du fichier de log : ", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("EA GEMINI SMC START");
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Print("Attention: Le trading automatique est desactive.");

   // Au demarrage, on declenche l'appel immediatement
   CallGemini();
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // On verifie si l'heure actuelle a depasse l'heure de la prochaine execution prevue
   if(TimeCurrent() >= nextCallTime)
   {
      CallGemini();
   }
}

//+------------------------------------------------------------------+
string GetData(int count)
{
   MqlRates r[]; 
   ArraySetAsSeries(r, true); 
   
   if(CopyRates(_Symbol, PERIOD_M5, 0, count, r) < count) 
   {
      Print("Erreur: Impossible de recuperer l'historique. Nouvel essai dans 10 secondes...");
      return "";
   }

   string s = "";
   for(int i = count - 1; i >= 0; i--)
   {
      s += "[H:" + DoubleToString(r[i].high, int(Digits())) + 
           " L:" + DoubleToString(r[i].low, int(Digits())) + 
           " C:" + DoubleToString(r[i].close, int(Digits())) + "]";
           
      if(i > 0) s += ", ";
   }

   return s;
}

//+------------------------------------------------------------------+
string Clean(string s)
{
   StringReplace(s, "\"", "");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   return s;
}

//+------------------------------------------------------------------+
string ExtractSignal(string jsonResponse)
{
   int startPos = StringFind(jsonResponse, "\"text\": \"");
   if(startPos == -1) return jsonResponse; 
   
   startPos += 9; 
   int endPos = StringFind(jsonResponse, "\"", startPos);
   if(endPos == -1) return jsonResponse;
   
   string signal = StringSubstr(jsonResponse, startPos, endPos - startPos);
   StringReplace(signal, "\\n", ""); 
   StringReplace(signal, "\n", "");
   StringReplace(signal, "\\\"", "\"");
   
   return signal;
}

//+------------------------------------------------------------------+
void CallGemini()
{
   int candlesToFetch = isFirstCall ? 48 : 10; 
   string data_str = GetData(candlesToFetch);
   
   // Si on n'a pas pu recuperer les bougies (MT5 non connecte), on retente dans 10s
   if(data_str == "") 
   {
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=" + API_KEY;
   string context = isFirstCall ? "4 hours of" : "last 10";
   
   string prompt = 
   "You are an expert SMC/ICT trader. Analyze this chronological sequence of " + context + " XAUUSD M5 candles " +
   "provided as High(H), Low(L), and Close(C): " + data_str + ". " +
   "Look strictly for this specific setup: " +
   "1. Creation of a clear Buy Side Liquidity (BSL) swing high. " +
   "2. A sweep of a previous Sell Side Liquidity (SSL) swing low (price drops below a low but rejects/closes higher). " +
   "3. Market structure shifting upwards to target the BSL high. " +
   "If this exact pattern is confirmed and it is time to enter a LONG trade towards the BSL, return the details of your analysis and give the details of the detected conditions." +
   "And in this case give also the details of the trade with SL and TP." +
   "If the pattern is incomplete, invalid, or bearish, return the details of the conditions that are ok and the conditions that are still needed.";
   
   string json = "{\"contents\":[{\"parts\":[{\"text\":\"" + Clean(prompt) + "\"}]}]}";
   
   string req_headers = "Content-Type: application/json\r\n";
   string res_headers = "";
   
   char payload_in[], payload_out[];
   
   StringToCharArray(json, payload_in, 0, WHOLE_ARRAY, CP_UTF8);
   ArrayResize(payload_in, StringLen(json)); 

   ResetLastError();

   int res = WebRequest("POST", url, req_headers, 10000, payload_in, payload_out, res_headers);
   
   // --- GESTION DES REPONSES ET DU CHRONOMETRE ---

   if(res == -1)
   {
      Print("Erreur locale WebRequest: ", GetLastError(), ". Nouvel essai dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10;
      return;
   }

   string out = CharArrayToString(payload_out, 0, -1, CP_UTF8);
   
   // --- TRAITEMENT DE LA REPONSE ---
   string finalDecision = ExtractSignal(out);
   
   // --- LOG UNIQUEMENT DU TEXTE LISIBLE ---
   LogResponse(finalDecision);
   
   // Affichage dans le terminal
   Print("DECISION SMC => ", finalDecision);

   // Erreur 503 (Surcharge) ou 429 (Trop de requetes)
   if(res == 503 || res == 429)
   {
      Print("Serveurs Gemini surcharges (Code ", res, "). Nouvel essai automatique dans 10 secondes...");
      nextCallTime = TimeCurrent() + 10;
      return; 
   }
   // Autres erreurs API critiques
   else if(res != 200)
   {
      Print("Erreur API Gemini fatale (Code ", res, ") : ", out, ". Nouvel essai dans 1 minute pour eviter le spam.");
      nextCallTime = TimeCurrent() + 60;
      return; 
   }

   // SUCCES TOTAL (HTTP 200)
   if(isFirstCall) 
   {
      Print("Contexte initial de 4 Heures analyse par l'IA avec succes.");
      isFirstCall = false; 
   }
   
   // Si tout s'est bien passe, on programme la prochaine analyse
   nextCallTime = TimeCurrent() + (IntervalMin * 60);
   Print("Prochaine analyse programmee dans ", IntervalMin, " minutes.");
}
