//+------------------------------------------------------------------+
//|                                              GeminiModelsAPI.mq5 |
//|                                    Appelle l'API Gemini Models   |  NE FONCTIONNE PAS ENCORE
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property script_show_inputs

// Paramètres d'entrée
input string ApiKey = "replace me";  // Clé API Gemini
input bool ShowAllDetails = true;  // Afficher tous les détails

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    // Vérifier que la clé API n'est pas vide
    if(StringLen(ApiKey) == 0)
    {
        Print("ERREUR: Veuillez entrer une clé API valide dans les paramètres!");
        return;
    }
    
    // Construire l'URL avec la clé API
    string url = "https://generativelanguage.googleapis.com/v1beta/models?key=" + ApiKey;
    
    Print("=== Début de l'appel API Gemini Models ===");
    Print("URL: ", url);
    
    // Préparer la requête - Version CORRECTE pour WebRequest
    string headers = "Content-Type: application/json\r\n";
    char postData[];
    char resultData[];
    string response;
    
    int timeout = 10000; // 10 secondes de timeout
    
    // WebRequest avec la signature correcte (5 paramètres)
    int res = WebRequest("GET", url, headers, timeout, postData, resultData, response);
    
    if(res == -1)
    {
        Print("Erreur WebRequest: ", GetLastError());
        Print("Vérifiez que WebRequest est autorisé:");
        Print("Outils -> Options -> Experts -> Autoriser les requêtes WebRequest");
        Print("Ajoutez l'URL: https://generativelanguage.googleapis.com/*");
        return;
    }
    
    if(res == 200)
    {
        Print("Succès! Code HTTP: ", res);
        Print("Taille de la réponse: ", StringLen(response), " caractères");
        
        // Sauvegarder la réponse brute dans un fichier pour débogage
        SaveResponseToFile(response);
        
        // Parser la réponse JSON
        ParseModelsResponse(response);
    }
    else
    {
        Print("Erreur HTTP: ", res);
        Print("Réponse: ", response);
        
        if(res == 403)
            Print("Erreur 403: Clé API invalide");
        else if(res == 404)
            Print("Erreur 404: Endpoint non trouvé");
        else if(res == 429)
            Print("Erreur 429: Trop de requêtes");
    }
}

//+------------------------------------------------------------------+
//| Sauvegarde la réponse dans un fichier                            |
//+------------------------------------------------------------------+
void SaveResponseToFile(string response)
{
    int handle = FileOpen("gemini_models_response.json", FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle != INVALID_HANDLE)
    {
        FileWrite(handle, response);
        FileClose(handle);
        Print("Réponse sauvegardée dans: gemini_models_response.json");
    }
}

//+------------------------------------------------------------------+
//| Parse la réponse JSON (version sans librairie externe)           |
//+------------------------------------------------------------------+
void ParseModelsResponse(string json)
{
    Print("\n=== PARSING DES DONNEES ===");
    
    // Chercher le tableau "models"
    int modelsStart = StringFind(json, "\"models\":");
    if(modelsStart == -1)
    {
        Print("ERREUR: 'models' non trouvé dans la réponse");
        return;
    }
    
    // Trouver le début du tableau [
    int arrayStart = StringFind(json, "[", modelsStart);
    if(arrayStart == -1)
    {
        Print("ERREUR: Début du tableau non trouvé");
        return;
    }
    
    // Trouver la fin du tableau ]
    int arrayEnd = FindMatchingBracket(json, arrayStart);
    if(arrayEnd == -1)
    {
        Print("ERREUR: Fin du tableau non trouvée");
        return;
    }
    
    // Extraire le tableau des modèles
    string modelsArray = StringSubstr(json, arrayStart, arrayEnd - arrayStart + 1);
    
    // Compter les modèles
    int modelCount = CountModels(modelsArray);
    Print("Nombre total de modèles: ", modelCount);
    Print("=========================================");
    
    // Extraire chaque modèle
    int displayLimit = ShowAllDetails ? modelCount : MathMin(10, modelCount);
    int currentModel = 0;
    int pos = 0;
    
    while(pos < StringLen(modelsArray) && currentModel < displayLimit)
    {
        // Trouver le début d'un objet modèle {
        int objStart = StringFind(modelsArray, "{", pos);
        if(objStart == -1) break;
        
        // Trouver la fin de l'objet }
        int objEnd = FindMatchingBracket(modelsArray, objStart);
        if(objEnd == -1) break;
        
        // Extraire l'objet modèle
        string modelObj = StringSubstr(modelsArray, objStart, objEnd - objStart + 1);
        
        // Parser l'objet modèle
        ParseModelObject(modelObj, currentModel + 1);
        
        currentModel++;
        pos = objEnd + 1;
    }
    
    if(!ShowAllDetails && modelCount > 10)
        Print("... et ", modelCount - 10, " autres modèles (modifiez 'ShowAllDetails' pour tout afficher)");
    
    // Afficher les statistiques
    DisplayStatistics(json);
    
    // Afficher les modèles recommandés
    ShowRecommendedModels(json);
}

//+------------------------------------------------------------------+
//| Trouve la parenthèse/bracket correspondante                      |
//+------------------------------------------------------------------+
int FindMatchingBracket(string text, int startPos)
{
    int openChar = StringGetCharacter(text, startPos);
    int closeChar;
    
    if(openChar == '{')
        closeChar = '}';
    else if(openChar == '[')
        closeChar = ']';
    else
        return -1;
    
    int depth = 1;
    for(int i = startPos + 1; i < StringLen(text); i++)
    {
        int ch = StringGetCharacter(text, i);
        if(ch == openChar)
            depth++;
        else if(ch == closeChar)
        {
            depth--;
            if(depth == 0)
                return i;
        }
    }
    
    return -1;
}

//+------------------------------------------------------------------+
//| Compte le nombre de modèles dans le tableau                      |
//+------------------------------------------------------------------+
int CountModels(string modelsArray)
{
    int count = 0;
    int pos = 0;
    
    while(pos < StringLen(modelsArray))
    {
        int objStart = StringFind(modelsArray, "{", pos);
        if(objStart == -1) break;
        
        int objEnd = FindMatchingBracket(modelsArray, objStart);
        if(objEnd == -1) break;
        
        count++;
        pos = objEnd + 1;
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Parse un objet modèle individuel                                 |
//+------------------------------------------------------------------+
void ParseModelObject(string modelObj, int index)
{
    Print("Modèle ", index, ":");
    
    // Extraire le nom complet
    string name = ExtractJsonString(modelObj, "name");
    if(name != "")
    {
        Print("  Nom complet: ", name);
        
        // Extraire le nom court
        int slashPos = StringFind(name, "/");
        if(slashPos != -1)
            Print("  Nom court: ", StringSubstr(name, slashPos + 1));
    }
    
    // Extraire le nom affiché
    string displayName = ExtractJsonString(modelObj, "displayName");
    if(displayName != "")
        Print("  Nom affiché: ", displayName);
    
    // Extraire la description
    string description = ExtractJsonString(modelObj, "description");
    if(description != "")
    {
        if(StringLen(description) > 100)
            description = StringSubstr(description, 0, 100) + "...";
        Print("  Description: ", description);
    }
    
    // Extraire les limites de tokens
    int inputTokenLimit = ExtractJsonInt(modelObj, "inputTokenLimit");
    if(inputTokenLimit > 0)
        Print("  Input Token Limit: ", FormatNumber(inputTokenLimit));
    
    int outputTokenLimit = ExtractJsonInt(modelObj, "outputTokenLimit");
    if(outputTokenLimit > 0)
        Print("  Output Token Limit: ", FormatNumber(outputTokenLimit));
    
    // Extraire les méthodes supportées
    string methods = ExtractJsonArray(modelObj, "supportedGenerationMethods");
    if(methods != "")
        Print("  Méthodes supportées: ", methods);
    
    // Extraire les paramètres optionnels
    double temperature = ExtractJsonDouble(modelObj, "temperature");
    if(temperature > 0)
        Print("  Temperature: ", DoubleToString(temperature, 2));
    
    double topP = ExtractJsonDouble(modelObj, "topP");
    if(topP > 0)
        Print("  Top P: ", DoubleToString(topP, 2));
    
    int topK = ExtractJsonInt(modelObj, "topK");
    if(topK > 0)
        Print("  Top K: ", topK);
    
    bool thinking = ExtractJsonBool(modelObj, "thinking");
    Print("  Thinking supporté: ", thinking ? "✓ Oui" : "✗ Non");
    
    Print("-----------------------------------------");
}

//+------------------------------------------------------------------+
//| Extrait une valeur string d'un objet JSON                        |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return "";
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return "";
    
    int quotePos = StringFind(json, "\"", colonPos);
    if(quotePos == -1) return "";
    
    int endQuotePos = StringFind(json, "\"", quotePos + 1);
    if(endQuotePos == -1) return "";
    
    return StringSubstr(json, quotePos + 1, endQuotePos - quotePos - 1);
}

//+------------------------------------------------------------------+
//| Extrait une valeur integer d'un objet JSON                       |
//+------------------------------------------------------------------+
int ExtractJsonInt(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return 0;
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return 0;
    
    int startPos = colonPos + 1;
    while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || 
          StringGetCharacter(json, startPos) == '\t' || StringGetCharacter(json, startPos) == '\n'))
        startPos++;
    
    string numStr = "";
    while(startPos < StringLen(json))
    {
        int ch = StringGetCharacter(json, startPos);
        if(ch >= '0' && ch <= '9')
            numStr += CharToString((uchar)ch);
        else if(ch == ',' || ch == '}' || ch == ']')
            break;
        else if(ch == '.' || ch == '-')
            numStr += CharToString((uchar)ch);
        else
            break;
        startPos++;
    }
    
    return (numStr != "") ? (int)StringToInteger(numStr) : 0;
}

//+------------------------------------------------------------------+
//| Extrait une valeur double d'un objet JSON                        |
//+------------------------------------------------------------------+
double ExtractJsonDouble(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return 0.0;
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return 0.0;
    
    int startPos = colonPos + 1;
    while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || 
          StringGetCharacter(json, startPos) == '\t' || StringGetCharacter(json, startPos) == '\n'))
        startPos++;
    
    string numStr = "";
    while(startPos < StringLen(json))
    {
        int ch = StringGetCharacter(json, startPos);
        if((ch >= '0' && ch <= '9') || ch == '.' || ch == '-')
            numStr += CharToString((uchar)ch);
        else if(ch == ',' || ch == '}' || ch == ']')
            break;
        else
            break;
        startPos++;
    }
    
    return (numStr != "") ? StringToDouble(numStr) : 0.0;
}

//+------------------------------------------------------------------+
//| Extrait une valeur boolean d'un objet JSON                       |
//+------------------------------------------------------------------+
bool ExtractJsonBool(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return false;
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return false;
    
    int startPos = colonPos + 1;
    while(startPos < StringLen(json) && (StringGetCharacter(json, startPos) == ' ' || 
          StringGetCharacter(json, startPos) == '\t' || StringGetCharacter(json, startPos) == '\n'))
        startPos++;
    
    // Vérifier "true" ou "false"
    if(StringSubstr(json, startPos, 4) == "true")
        return true;
    else if(StringSubstr(json, startPos, 5) == "false")
        return false;
    
    return false;
}

//+------------------------------------------------------------------+
//| Extrait un tableau JSON                                         |
//+------------------------------------------------------------------+
string ExtractJsonArray(string json, string key)
{
    string searchKey = "\"" + key + "\"";
    int keyPos = StringFind(json, searchKey);
    if(keyPos == -1) return "";
    
    int colonPos = StringFind(json, ":", keyPos);
    if(colonPos == -1) return "";
    
    int arrayStart = StringFind(json, "[", colonPos);
    if(arrayStart == -1) return "";
    
    int arrayEnd = FindMatchingBracket(json, arrayStart);
    if(arrayEnd == -1) return "";
    
    string arrayContent = StringSubstr(json, arrayStart + 1, arrayEnd - arrayStart - 1);
    
    // Nettoyer le tableau pour l'affichage
    StringReplace(arrayContent, "\"", "");
    StringReplace(arrayContent, "\n", "");
    StringReplace(arrayContent, "\r", "");
    
    return arrayContent;
}

//+------------------------------------------------------------------+
//| Formate les grands nombres                                       |
//+------------------------------------------------------------------+
string FormatNumber(int number)
{
    if(number < 1000)
        return IntegerToString(number);
    
    string result = "";
    int temp = number;
    int count = 0;
    
    while(temp > 0)
    {
        if(count > 0 && count % 3 == 0)
            result = "," + result;
        result = IntegerToString(temp % 10) + result;
        temp /= 10;
        count++;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Affiche les statistiques globales                                |
//+------------------------------------------------------------------+
void DisplayStatistics(string json)
{
    Print("\n=== STATISTIQUES GLOBALES ===");
    
    // Compter les modèles par type
    int textModels = 0;
    int embeddingModels = 0;
    
    int modelsStart = StringFind(json, "\"models\":");
    if(modelsStart == -1) return;
    
    int arrayStart = StringFind(json, "[", modelsStart);
    if(arrayStart == -1) return;
    
    int arrayEnd = FindMatchingBracket(json, arrayStart);
    if(arrayEnd == -1) return;
    
    string modelsArray = StringSubstr(json, arrayStart, arrayEnd - arrayStart + 1);
    
    int pos = 0;
    while(pos < StringLen(modelsArray))
    {
        int objStart = StringFind(modelsArray, "{", pos);
        if(objStart == -1) break;
        
        int objEnd = FindMatchingBracket(modelsArray, objStart);
        if(objEnd == -1) break;
        
        string modelObj = StringSubstr(modelsArray, objStart, objEnd - objStart + 1);
        
        string methods = ExtractJsonArray(modelObj, "supportedGenerationMethods");
        if(StringFind(methods, "generateContent") != -1)
            textModels++;
        if(StringFind(methods, "embedContent") != -1)
            embeddingModels++;
        
        pos = objEnd + 1;
    }
    
    Print("Modèles de génération de texte: ", textModels);
    Print("Modèles d'embedding: ", embeddingModels);
    
    // Pagination
    string nextPageToken = ExtractJsonString(json, "nextPageToken");
    if(nextPageToken != "")
        Print("⚠ Note: D'autres modèles sont disponibles (pagination)");
}

//+------------------------------------------------------------------+
//| Affiche les modèles recommandés                                  |
//+------------------------------------------------------------------+
void ShowRecommendedModels(string json)
{
    Print("\n=== MODÈLES RECOMMANDÉS ===");
    
    // Chercher les modèles populaires
    string popularModels[] = {
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        "gemini-embedding-2"
    };
    
    for(int i = 0; i < ArraySize(popularModels); i++)
    {
        int pos = StringFind(json, popularModels[i]);
        if(pos != -1)
        {
            Print(popularModels[i]);
            
            // Essayer de trouver le displayName à proximité
            int searchStart = (pos > 500) ? pos - 500 : 0;
            int searchEnd = pos + 500;
            if(searchEnd > StringLen(json)) searchEnd = StringLen(json);
            
            string searchArea = StringSubstr(json, searchStart, searchEnd - searchStart);
            string displayName = ExtractJsonString(searchArea, "displayName");
            
            if(displayName != "")
                Print("  → ", displayName);
        }
    }
}

//+------------------------------------------------------------------+
//| NOTE IMPORTANTE:                                                  |
//| 1. Avant d'utiliser, allez dans Outils -> Options -> Experts     |
//| 2. Cochez "Autoriser les requêtes WebRequest"                     |
//| 3. Ajoutez l'URL: https://generativelanguage.googleapis.com/*    |
//| 4. Redémarrez MetaTrader 5                                       |
//+------------------------------------------------------------------+


/*
{
  "models": [
    {
      "name": "models/gemini-2.5-flash",
      "version": "001",
      "displayName": "Gemini 2.5 Flash",
      "description": "Stable version of Gemini 2.5 Flash, our mid-size multimodal model that supports up to 1 million tokens, released in June of 2025.",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-2.5-pro",
      "version": "2.5",
      "displayName": "Gemini 2.5 Pro",
      "description": "Stable release (June 17th, 2025) of Gemini 2.5 Pro",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-2.0-flash",
      "version": "2.0",
      "displayName": "Gemini 2.0 Flash",
      "description": "Gemini 2.0 Flash",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 40,
      "maxTemperature": 2
    },
    {
      "name": "models/gemini-2.0-flash-001",
      "version": "2.0",
      "displayName": "Gemini 2.0 Flash 001",
      "description": "Stable version of Gemini 2.0 Flash, our fast and versatile multimodal model for scaling across diverse tasks, released in January of 2025.",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 40,
      "maxTemperature": 2
    },
    {
      "name": "models/gemini-2.0-flash-lite-001",
      "version": "2.0",
      "displayName": "Gemini 2.0 Flash-Lite 001",
      "description": "Stable version of Gemini 2.0 Flash-Lite",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 40,
      "maxTemperature": 2
    },
    {
      "name": "models/gemini-2.0-flash-lite",
      "version": "2.0",
      "displayName": "Gemini 2.0 Flash-Lite",
      "description": "Gemini 2.0 Flash-Lite",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 40,
      "maxTemperature": 2
    },
    {
      "name": "models/gemini-2.5-flash-preview-tts",
      "version": "gemini-2.5-flash-exp-tts-2025-05-19",
      "displayName": "Gemini 2.5 Flash Preview TTS",
      "description": "Gemini 2.5 Flash Preview TTS",
      "inputTokenLimit": 8192,
      "outputTokenLimit": 16384,
      "supportedGenerationMethods": [
        "countTokens",
        "generateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2
    },
    {
      "name": "models/gemini-2.5-pro-preview-tts",
      "version": "gemini-2.5-pro-preview-tts-2025-05-19",
      "displayName": "Gemini 2.5 Pro Preview TTS",
      "description": "Gemini 2.5 Pro Preview TTS",
      "inputTokenLimit": 8192,
      "outputTokenLimit": 16384,
      "supportedGenerationMethods": [
        "countTokens",
        "generateContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2
    },
    {
      "name": "models/gemma-4-26b-a4b-it",
      "version": "001",
      "displayName": "Gemma 4 26B A4B IT",
      "description": "Gemma 4 26B A4B IT",
      "inputTokenLimit": 262144,
      "outputTokenLimit": 32768,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemma-4-31b-it",
      "version": "001",
      "displayName": "Gemma 4 31B IT",
      "description": "Gemma 4 31B IT",
      "inputTokenLimit": 262144,
      "outputTokenLimit": 32768,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-flash-latest",
      "version": "Gemini Flash Latest",
      "displayName": "Gemini Flash Latest",
      "description": "Latest release of Gemini Flash",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-flash-lite-latest",
      "version": "Gemini Flash-Lite Latest",
      "displayName": "Gemini Flash-Lite Latest",
      "description": "Latest release of Gemini Flash-Lite",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-pro-latest",
      "version": "Gemini Pro Latest",
      "displayName": "Gemini Pro Latest",
      "description": "Latest release of Gemini Pro",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-2.5-flash-lite",
      "version": "001",
      "displayName": "Gemini 2.5 Flash-Lite",
      "description": "Stable version of Gemini 2.5 Flash-Lite, released in July of 2025",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-2.5-flash-image",
      "version": "2.0",
      "displayName": "Nano Banana",
      "description": "Gemini 2.5 Flash Preview Image",
      "inputTokenLimit": 32768,
      "outputTokenLimit": 32768,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 1
    },
    {
      "name": "models/gemini-3-pro-preview",
      "version": "3-pro-preview-11-2025",
      "displayName": "Gemini 3 Pro Preview",
      "description": "Gemini 3 Pro Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-3-flash-preview",
      "version": "3-flash-preview-12-2025",
      "displayName": "Gemini 3 Flash Preview",
      "description": "Gemini 3 Flash Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-3.1-pro-preview",
      "version": "3.1-pro-preview-01-2026",
      "displayName": "Gemini 3.1 Pro Preview",
      "description": "Gemini 3.1 Pro Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-3.1-pro-preview-customtools",
      "version": "3.1-pro-preview-01-2026",
      "displayName": "Gemini 3.1 Pro Preview Custom Tools",
      "description": "Gemini 3.1 Pro Preview optimized for custom tool usage",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-3.1-flash-lite-preview",
      "version": "3.1-flash-lite-preview-03-2026",
      "displayName": "Gemini 3.1 Flash Lite Preview",
      "description": "Gemini 3.1 Flash Lite Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-3.1-flash-lite",
      "version": "3.1-flash-lite-05-2026",
      "displayName": "Gemini 3.1 Flash Lite",
      "description": "Gemini 3.1 Flash Lite",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-3-pro-image-preview",
      "version": "3.0",
      "displayName": "Nano Banana Pro",
      "description": "Gemini 3 Pro Image Preview",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 32768,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 1,
      "thinking": true
    },
    {
      "name": "models/nano-banana-pro-preview",
      "version": "3.0",
      "displayName": "Nano Banana Pro",
      "description": "Gemini 3 Pro Image Preview",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 32768,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 1,
      "thinking": true
    },
    {
      "name": "models/gemini-3.1-flash-image-preview",
      "version": "3.0",
      "displayName": "Nano Banana 2",
      "description": "Gemini 3.1 Flash Image Preview.",
      "inputTokenLimit": 65536,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 1,
      "thinking": true
    },
    {
      "name": "models/gemini-3.5-flash",
      "version": "3.5-flash-05-2026",
      "displayName": "Gemini 3.5 Flash",
      "description": "Gemini 3.5 Flash",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/lyria-3-clip-preview",
      "version": "lyria-3-clip-preview",
      "displayName": "Lyria 3 Clip Preview",
      "description": "Lyria 3 30s model Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2
    },
    {
      "name": "models/lyria-3-pro-preview",
      "version": "lyria-3-pro-preview",
      "displayName": "Lyria 3 Pro Preview",
      "description": "Lyria 3 Pro Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2
    },
    {
      "name": "models/gemini-3.1-flash-tts-preview",
      "version": "3.1-flash-tts-preview",
      "displayName": "Gemini 3.1 Flash TTS Preview",
      "description": "Gemini 3.1 Flash TTS Preview",
      "inputTokenLimit": 8192,
      "outputTokenLimit": 16384,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-robotics-er-1.5-preview",
      "version": "1.5-preview",
      "displayName": "Gemini Robotics-ER 1.5 Preview",
      "description": "Gemini Robotics-ER 1.5 Preview",
      "inputTokenLimit": 1048576,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-robotics-er-1.6-preview",
      "version": "1.6-preview",
      "displayName": "Gemini Robotics-ER 1.6 Preview",
      "description": "Gemini Robotics-ER 1.6 Preview",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens",
        "createCachedContent",
        "batchGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-2.5-computer-use-preview-10-2025",
      "version": "Gemini 2.5 Computer Use Preview 10-2025",
      "displayName": "Gemini 2.5 Computer Use Preview 10-2025",
      "description": "Gemini 2.5 Computer Use Preview 10-2025",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/antigravity-preview-05-2026",
      "version": "0.1",
      "displayName": "Antigravity Agent Preview",
      "description": "Preview release of Antigravity Agent (05-2026)",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ]
    },
    {
      "name": "models/deep-research-max-preview-04-2026",
      "version": "deepthink-exp-05-20",
      "displayName": "Deep Research Max Preview (Apr-21-2026)",
      "description": "Preview release (April 21st, 2026) of Deep Research Max",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/deep-research-preview-04-2026",
      "version": "deepthink-exp-05-20",
      "displayName": "Deep Research Preview (Apr-21-2026)",
      "description": "Preview release (April 21th, 2026) of Deep Research",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/deep-research-pro-preview-12-2025",
      "version": "deepthink-exp-05-20",
      "displayName": "Deep Research Pro Preview (Dec-12-2025)",
      "description": "Preview release (December 12th, 2025) of Deep Research Pro",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 65536,
      "supportedGenerationMethods": [
        "generateContent",
        "countTokens"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-embedding-001",
      "version": "001",
      "displayName": "Gemini Embedding 001",
      "description": "Obtain a distributed representation of a text.",
      "inputTokenLimit": 2048,
      "outputTokenLimit": 1,
      "supportedGenerationMethods": [
        "embedContent",
        "countTextTokens",
        "countTokens",
        "asyncBatchEmbedContent"
      ]
    },
    {
      "name": "models/gemini-embedding-2-preview",
      "version": "2",
      "displayName": "Gemini Embedding 2 Preview",
      "description": "Obtain a distributed representation of multimodal content.",
      "inputTokenLimit": 8192,
      "outputTokenLimit": 1,
      "supportedGenerationMethods": [
        "embedContent",
        "countTextTokens",
        "countTokens",
        "asyncBatchEmbedContent"
      ]
    },
    {
      "name": "models/gemini-embedding-2",
      "version": "2",
      "displayName": "Gemini Embedding 2",
      "description": "Obtain a distributed representation of multimodal content.",
      "inputTokenLimit": 8192,
      "outputTokenLimit": 1,
      "supportedGenerationMethods": [
        "embedContent",
        "countTextTokens",
        "countTokens",
        "asyncBatchEmbedContent"
      ]
    },
    {
      "name": "models/aqa",
      "version": "001",
      "displayName": "Model that performs Attributed Question Answering.",
      "description": "Model trained to return answers to questions that are grounded in provided sources, along with estimating answerable probability.",
      "inputTokenLimit": 7168,
      "outputTokenLimit": 1024,
      "supportedGenerationMethods": [
        "generateAnswer"
      ],
      "temperature": 0.2,
      "topP": 1,
      "topK": 40
    },
    {
      "name": "models/imagen-4.0-generate-001",
      "version": "001",
      "displayName": "Imagen 4",
      "description": "Vertex served Imagen 4.0 model",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predict"
      ]
    },
    {
      "name": "models/imagen-4.0-ultra-generate-001",
      "version": "001",
      "displayName": "Imagen 4 Ultra",
      "description": "Vertex served Imagen 4.0 ultra model",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predict"
      ]
    },
    {
      "name": "models/imagen-4.0-fast-generate-001",
      "version": "001",
      "displayName": "Imagen 4 Fast",
      "description": "Vertex served Imagen 4.0 Fast model",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predict"
      ]
    },
    {
      "name": "models/veo-2.0-generate-001",
      "version": "2.0",
      "displayName": "Veo 2",
      "description": "Vertex served Veo 2 model. Access to this model requires billing to be enabled on the associated Google Cloud Platform account. Please visit https://console.cloud.google.com/billing to enable it.",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
    {
      "name": "models/veo-3.0-generate-001",
      "version": "3.0",
      "displayName": "Veo 3",
      "description": "Veo 3",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
    {
      "name": "models/veo-3.0-fast-generate-001",
      "version": "3.0",
      "displayName": "Veo 3 fast",
      "description": "Veo 3 fast",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
    {
      "name": "models/veo-3.1-generate-preview",
      "version": "3.1",
      "displayName": "Veo 3.1",
      "description": "Veo 3.1",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
    {
      "name": "models/veo-3.1-fast-generate-preview",
      "version": "3.1",
      "displayName": "Veo 3.1 fast",
      "description": "Veo 3.1 fast",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
    {
      "name": "models/veo-3.1-lite-generate-preview",
      "version": "3.1",
      "displayName": "Veo 3.1 lite",
      "description": "Veo 3.1 lite",
      "inputTokenLimit": 480,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "predictLongRunning"
      ]
    },
    {
      "name": "models/gemini-2.5-flash-native-audio-latest",
      "version": "Gemini 2.5 Flash Native Audio Latest",
      "displayName": "Gemini 2.5 Flash Native Audio Latest",
      "description": "Latest release of Gemini 2.5 Flash Native Audio",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "countTokens",
        "bidiGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    },
    {
      "name": "models/gemini-2.5-flash-native-audio-preview-09-2025",
      "version": "gemini-2.5-flash-preview-native-audio-dialog-2025-05-19",
      "displayName": "Gemini 2.5 Flash Native Audio Preview 09-2025",
      "description": "Gemini 2.5 Flash Native Audio Preview 09-2025",
      "inputTokenLimit": 131072,
      "outputTokenLimit": 8192,
      "supportedGenerationMethods": [
        "countTokens",
        "bidiGenerateContent"
      ],
      "temperature": 1,
      "topP": 0.95,
      "topK": 64,
      "maxTemperature": 2,
      "thinking": true
    }
  ],
  "nextPageToken": "CjRtb2RlbHMvZ2VtaW5pLTIuNS1mbGFzaC1uYXRpdmUtYXVkaW8tcHJldmlldy0wOS0yMDI1"
}
*/
