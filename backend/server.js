import "dotenv/config";

import cors from "cors";
import express from "express";
import rateLimit from "express-rate-limit";
import helmet from "helmet";
import OpenAI from "openai";
import { z } from "zod";

const app = express();
const port = Number(process.env.PORT || 3000);
const openAIAPIKey = process.env.OPENAI_API_KEY || "";
const openAIModel = process.env.OPENAI_MODEL || "gpt-4o-mini";
const allowedOrigin = process.env.ALLOWED_ORIGIN || "";

if (!openAIAPIKey) {
    console.warn("OPENAI_API_KEY is missing. AI endpoints will fail until it is set.");
}

const openai = new OpenAI({
    apiKey: openAIAPIKey
});

const phraseRequestSchema = z.object({
    phrase: z.string().trim().min(1).max(120)
});

const sentenceResponseSchema = {
    name: "sentence_bundle",
    schema: {
        type: "object",
        additionalProperties: false,
        properties: {
            sentences: {
                type: "array",
                minItems: 4,
                maxItems: 4,
                items: {
                    type: "string"
                }
            }
        },
        required: ["sentences"]
    },
    strict: true
};

const difficultyResponseSchema = {
    name: "difficulty_level",
    schema: {
        type: "object",
        additionalProperties: false,
        properties: {
            level: {
                type: "integer",
                minimum: 1,
                maximum: 5
            }
        },
        required: ["level"]
    },
    strict: true
};

const hintResponseSchema = {
    name: "phrase_hint",
    schema: {
        type: "object",
        additionalProperties: false,
        properties: {
            hint: {
                type: "string"
            }
        },
        required: ["hint"]
    },
    strict: true
};

const meaningResponseSchema = {
    name: "phrase_definition",
    schema: {
        type: "object",
        additionalProperties: false,
        properties: {
            meaning: {
                type: "string"
            }
        },
        required: ["meaning"]
    },
    strict: true
};

app.set("trust proxy", 1);
app.use(helmet());
app.use(express.json({ limit: "16kb" }));
app.use(
    cors({
        origin(origin, callback) {
            if (!allowedOrigin || !origin || origin === allowedOrigin) {
                callback(null, true);
                return;
            }

            callback(new Error("Origin not allowed by CORS"));
        }
    })
);

app.use(
    rateLimit({
        windowMs: 60 * 1000,
        max: 60,
        standardHeaders: true,
        legacyHeaders: false,
        message: {
            error: "Too many requests. Please try again in a minute."
        }
    })
);

app.get("/health", (_request, response) => {
    response.json({
        ok: true
    });
});

app.post("/generate-sentence", async (request, response) => {
    const parsed = phraseRequestSchema.safeParse(request.body);
    if (!parsed.success) {
        response.status(400).json({
            error: "Invalid request body."
        });
        return;
    }

    try {
        const result = await openai.responses.create({
            model: openAIModel,
            input: [
                {
                    role: "system",
                    content: [
                        {
                            type: "input_text",
                            text: [
                                "You create short, natural sentence prompts for English vocabulary practice.",
                                "Return exactly four English sentences.",
                                "Each sentence must contain the target phrase exactly once.",
                                "The learner must be able to answer with the exact saved phrase unchanged.",
                                "Do not require any tense change, plural change, article change, or other grammatical transformation.",
                                "If the phrase is a base-form verb or verb phrase, write the sentence so that the base form fits naturally as written.",
                                "Keep sentences clear, natural, and between 8 and 20 words.",
                                "Use the phrase naturally, not as a dictionary definition.",
                                "Reject any sentence where the exact phrase would sound ungrammatical when inserted into the blank."
                            ].join(" ")
                        }
                    ]
                },
                {
                    role: "user",
                    content: [
                        {
                            type: "input_text",
                            text: `Generate four different natural usage sentences for this exact phrase: ${parsed.data.phrase}`
                        }
                    ]
                }
            ],
            text: {
                format: {
                    type: "json_schema",
                    ...sentenceResponseSchema
                }
            }
        });

        const payload = extractJSONObject(result.output_text);
        const parsedPayload = JSON.parse(payload);
        response.json(parsedPayload);
    } catch (error) {
        logServerError("generate-sentence", error);
        response.status(503).json({
            error: "Sentence generation is temporarily unavailable."
        });
    }
});

app.post("/classify-difficulty", async (request, response) => {
    const parsed = phraseRequestSchema.safeParse(request.body);
    if (!parsed.success) {
        response.status(400).json({
            error: "Invalid request body."
        });
        return;
    }

    try {
        const result = await openai.responses.create({
            model: openAIModel,
            input: [
                {
                    role: "system",
                    content: [
                        {
                            type: "input_text",
                            text: [
                                "You estimate how difficult an English word or phrase is for an English learner using a CEFR-like 1 to 5 scale.",
                                "Consider frequency, formality, abstractness, figurative meaning, idiomaticity, and how likely a learner is to meet or actively use the item.",
                                "Pay special attention to multiword phrases, idioms, figurative expressions, phrasal verbs, and fixed expressions.",
                                "Do not rate only by the difficulty of the individual words; judge the whole expression as a vocabulary item.",
                                "If a phrase is idiomatic, non-literal, formal, legal, academic, nuanced, or uncommon in everyday speech, raise the level accordingly.",
                                "Use these levels:",
                                "Level 1 = Beginner / A1: very common, concrete, everyday words and phrases understood by basic learners.",
                                "Level 2 = Elementary / A2: common daily vocabulary and simple expressions, still mostly concrete and familiar.",
                                "Level 3 = Intermediate / B1-B2: less common but still broadly useful vocabulary, including many workplace, media, and abstract items.",
                                "Level 4 = Advanced / C1: formal, nuanced, low-frequency, idiomatic, academic, or professional vocabulary.",
                                "Level 5 = Expert / C2+: rare, highly idiomatic, literary, legal, technical, or especially difficult expressions.",
                                "When unsure, prefer the level that best reflects real learner difficulty rather than word length.",
                                "Return only the single best overall difficulty level."
                            ].join(" ")
                        }
                    ]
                },
                {
                    role: "user",
                    content: [
                        {
                            type: "input_text",
                            text: `Classify this English word or phrase on a 1 to 5 difficulty scale: ${parsed.data.phrase}`
                        }
                    ]
                }
            ],
            text: {
                format: {
                    type: "json_schema",
                    ...difficultyResponseSchema
                }
            }
        });

        const payload = extractJSONObject(result.output_text);
        const parsedPayload = JSON.parse(payload);
        response.json(parsedPayload);
    } catch (error) {
        logServerError("classify-difficulty", error);
        response.status(503).json({
            error: "Difficulty classification is temporarily unavailable."
        });
    }
});

app.post("/explain-phrase", async (request, response) => {
    const parsed = phraseRequestSchema.safeParse(request.body);
    if (!parsed.success) {
        response.status(400).json({
            error: "Invalid request body."
        });
        return;
    }

    try {
        const result = await openai.responses.create({
            model: openAIModel,
            input: [
                {
                    role: "system",
                    content: [
                        {
                            type: "input_text",
                            text: [
                                "You explain the meaning of an English word or phrase for language learners.",
                                "Return one short plain-English hint.",
                                "Do not repeat the phrase itself.",
                                "Keep it under 18 words."
                            ].join(" ")
                        }
                    ]
                },
                {
                    role: "user",
                    content: [
                        {
                            type: "input_text",
                            text: `Explain the meaning of this English word or phrase in one short hint: ${parsed.data.phrase}`
                        }
                    ]
                }
            ],
            text: {
                format: {
                    type: "json_schema",
                    ...hintResponseSchema
                }
            }
        });

        const payload = extractJSONObject(result.output_text);
        const parsedPayload = JSON.parse(payload);
        response.json(parsedPayload);
    } catch (error) {
        logServerError("explain-phrase", error);
        response.status(503).json({
            error: "Meaning hint is temporarily unavailable."
        });
    }
});

app.post("/define-phrase", async (request, response) => {
    const parsed = phraseRequestSchema.safeParse(request.body);
    if (!parsed.success) {
        response.status(400).json({
            error: "Invalid request body."
        });
        return;
    }

    try {
        const result = await openai.responses.create({
            model: openAIModel,
            input: [
                {
                    role: "system",
                    content: [
                        {
                            type: "input_text",
                            text: [
                                "You explain the meaning of an English word or phrase for language learners.",
                                "Return a full but compact explanation in plain English.",
                                "If the item is idiomatic or figurative, explain the figurative meaning clearly.",
                                "Keep the answer to 2 or 3 sentences.",
                                "Do not use bullet points."
                            ].join(" ")
                        }
                    ]
                },
                {
                    role: "user",
                    content: [
                        {
                            type: "input_text",
                            text: `Give the full meaning of this English word or phrase: ${parsed.data.phrase}`
                        }
                    ]
                }
            ],
            text: {
                format: {
                    type: "json_schema",
                    ...meaningResponseSchema
                }
            }
        });

        const payload = extractJSONObject(result.output_text);
        const parsedPayload = JSON.parse(payload);
        response.json(parsedPayload);
    } catch (error) {
        logServerError("define-phrase", error);
        response.status(503).json({
            error: "Full meaning is temporarily unavailable."
        });
    }
});

app.use((error, _request, response, _next) => {
    if (error?.message === "Origin not allowed by CORS") {
        response.status(403).json({
            error: "This origin is not allowed."
        });
        return;
    }

    logServerError("unhandled", error);
    response.status(500).json({
        error: "Internal server error."
    });
});

app.listen(port, () => {
    console.log(`LexiCue backend listening on port ${port}`);
});

function extractJSONObject(outputText) {
    if (typeof outputText !== "string" || !outputText.trim()) {
        throw new Error("Missing output_text from OpenAI response.");
    }

    return outputText;
}

function logServerError(scope, error) {
    console.error(`[${scope}]`, error);
}
