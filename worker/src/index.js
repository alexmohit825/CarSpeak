import { AG_PORTFOLIO_SEED } from './ag_portfolio_seed.js';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-CarSpeak-Client',
};

const SEEDED_CONVERSATIONS = [
  {
    id: 'conv-radix-pjk-2026',
    title: 'Radix & PJKPredict Spine Biomechanics Review',
    projectId: 'radix',
        projectName: 'Radix (RadixNeuro) / PJKPredict',
    persona: 'surgical',
    createdAt: '2026-10-17T16:30:00Z',
    updatedAt: '2026-10-18T08:15:00Z',
    summary: 'Reviewed C5-T1 radiculopathy dermatome-myotome localization in Radix and proximal junctional kyphosis (PJK) UIV selection thresholds in PJKPredict.',
    turns: [
      {
        role: 'user',
        text: 'Let us review where we left off on Radix and PJKPredict spinopelvic alignment thresholds.',
        timestamp: '2026-10-18T08:12:00Z'
      },
      {
        role: 'model',
        text: 'In Radix, we finalized the cervical and lumbosacral radiculopathy localization matrix correlating disc herniation zones with motor/reflex deficits. In PJKPredict, we anchored the preoperative sagittal alignment risk calculator around PI-LL mismatch, SVA, and UIV selection at the thoracolumbar junction. Ready to pick up on prophylactic tether scoring or Radix TestFlight refinements whenever you are.',
        timestamp: '2026-10-18T08:12:18Z'
      }
    ]
  },
  {
    id: 'conv-duralguard-vigilor-2026',
    title: 'DuralGuard & VigilOR Intraoperative Safety Suite',
    projectId: 'duralguard',
    projectName: 'DuralGuard & VigilOR Sentinel',
    persona: 'surgical',
    createdAt: '2026-10-15T17:10:00Z',
    updatedAt: '2026-10-17T18:45:00Z',
    summary: 'Discussed watertight dural closure risk stratification in DuralGuard and hands-free intraoperative IONM / blood-loss timer milestones in VigilOR.',
    turns: [
      {
        role: 'user',
        text: 'Summarize our current architecture on DuralGuard and VigilOR Sentinel.',
        timestamp: '2026-10-17T18:40:00Z'
      },
      {
        role: 'model',
        text: 'DuralGuard stratifies postoperative CSF leak and pseudomeningocele risk based on durotomy location, repair technique, and graft selection. VigilOR Sentinel tracks intraoperative neuromonitoring alerts, EBL intervals, and surgical milestones. Next on the roadmap is cross-linking intraoperative dural tear events in VigilOR directly into DuralGuard closure protocols.',
        timestamp: '2026-10-17T18:41:00Z'
      }
    ]
  },
  {
    id: 'conv-mdesq-cptarmor-2026',
    title: 'MDEsq & CPTArmor Medicolegal & Coding Strategy',
    projectId: 'mdesq',
    projectName: 'MDEsq / CPTArmor / JurisShield',
    persona: 'executive',
    createdAt: '2026-10-14T15:00:00Z',
    updatedAt: '2026-10-16T19:20:00Z',
    summary: 'Aligned CausationMatrix and MDEsq expert witness chronology extraction with CPTArmor operative note NCCI unbundling defense.',
    turns: [
      {
        role: 'user',
        text: 'How are MDEsq, CausationMatrix, and CPTArmor positioned across our medicolegal and billing portfolio?',
        timestamp: '2026-10-16T19:18:00Z'
      },
      {
        role: 'model',
        text: 'MDEsq and CausationMatrix handle forensic chronology synthesis, proximate cause biomechanics, and standard-of-care analysis for IMEs and malpractice defense, while CPTArmor and PreAuthIQ protect neurosurgical operative documentation against payer NCCI bundling and prior-authorization denials.',
        timestamp: '2026-10-16T19:19:00Z'
      }
    ]
  },
  {
    id: 'conv-futurus-learnlab-2026',
    title: 'Futurus AI Wealth & LearnLab Quant Engine',
    projectId: 'futurus',
    projectName: 'Futurus AI / LearnLab / ETF-Rebalancer',
    persona: 'executive',
    createdAt: '2026-10-13T14:00:00Z',
    updatedAt: '2026-10-17T20:50:00Z',
    summary: 'Reviewed Monte Carlo wealth trajectory modeling in Futurus, interactive quant curriculum modules in LearnLab, and OTM cash-secured put screening.',
    turns: [
      {
        role: 'user',
        text: 'Give me a quick status check on Futurus, LearnLab, and our Put Option Screener.',
        timestamp: '2026-10-17T20:48:00Z'
      },
      {
        role: 'model',
        text: 'LearnLab is live with interactive financial education modules, Futurus models multi-decade wealth trajectories, and Put Option Screener filters high-yield OTM cash-secured puts with ETF-Rebalancer managing tax-efficient core allocations.',
        timestamp: '2026-10-17T20:49:00Z'
      }
    ]
  }
];

const PERSONA_PROMPTS = {
  executive: `You are CarSpeak (Executive Chief of Staff Mode), Dr. A. Alex Mohit's personal, unrestricted, hands-free in-car conversational AI partner running over Apple CarPlay.
Keep spoken responses concise, high-density, direct, and natural for eyes-free driving (2 to 4 crisp sentences unless asked for deep detail). Never use markdown bullet symbols or formatting artifacts in spoken output.`,
  surgical: `You are CarSpeak (Neurosurgical & Clinical Consult Mode) for Dr. A. Alex Mohit, board-certified neurosurgeon and medical innovator.
Use rigorous neurosurgical, spinal biomechanics, neuro-oncological, and clinical trial nomenclature. Keep responses concise and optimized for hands-free cabin audio.`,
  architect: `You are CarSpeak (Principal Systems Architect Mode) for Dr. A. Alex Mohit.
Focus on iOS 18 Swift/SwiftUI, CarPlay, WebRTC/5G network resilience, Cloudflare Workers/KV, Gemini 3.8 Live, and full-stack architecture across his Antigravity portfolio.`,
  memo: `You are CarSpeak (Hands-Free Action & Roadmap Capture Mode) for Dr. A. Alex Mohit.
Help Dr. Mohit brainstorm, structure, and log concrete roadmap notes and action items into his Antigravity projects using save_ag_project_roadmap_note.`
};

const LIVE_VOICE_TOOLS = [
  {
    name: 'list_archived_conversations',
    behavior: 'NON_BLOCKING',
    description: 'Lists Dr. Mohit\'s previous archived conversations in CarSpeak, optionally filtered by keyword or Antigravity project name.',
    parameters: {
      type: 'OBJECT',
      properties: {
        query: {
          type: 'STRING',
          description: 'Optional topic or Antigravity project name filter (e.g., "Radix", "DuralGuard", "MDEsq", "Futurus"). Leave empty to list recent conversations.'
        }
      }
    }
  },
  {
    name: 'switch_to_conversation',
    behavior: 'NON_BLOCKING',
    description: 'Switches the active CarSpeak session to a specific previous archived conversation by topic, title, ID, or project name so Dr. Mohit can pick up right where he left off.',
    parameters: {
      type: 'OBJECT',
      properties: {
        target_query: {
          type: 'STRING',
          description: 'The conversation title, topic keyword, project name, or ID to switch to (e.g., "DuralGuard", "Radix", "MDEsq", "Futurus").'
        }
      },
      required: ['target_query']
    }
  },
  {
    name: 'start_new_conversation',
    behavior: 'NON_BLOCKING',
    description: 'Archives the current conversation and starts a brand-new conversation thread, optionally anchored on a specific Antigravity project.',
    parameters: {
      type: 'OBJECT',
      properties: {
        title: {
          type: 'STRING',
          description: 'Title for the new conversation thread.'
        },
        project_name: {
          type: 'STRING',
          description: 'Optional Antigravity project name to link to this new conversation.'
        }
      },
      required: ['title']
    }
  },
  {
    name: 'get_ag_project_dossier',
    behavior: 'NON_BLOCKING',
    description: 'Retrieves the detailed dossier, architecture, tech stack, Bundle ID, recent focus, and saved roadmap notes for any of Dr. Mohit\'s 56+ Antigravity (AG) projects.',
    parameters: {
      type: 'OBJECT',
      properties: {
        project_name: {
          type: 'STRING',
          description: 'Name of the Antigravity project (e.g., "Radix", "SnapEdge", "LearnLab", "DuralGuard", "HardwareHazard", "PJKPredict", "Spine-Measure", "VigilOR", "MDEsq", "CPTArmor", "JurisShield", "Hands-Free Lingo", "SomnaLux", "TrialCompass").'
        }
      },
      required: ['project_name']
    }
  },
  {
    name: 'save_ag_project_roadmap_note',
    behavior: 'NON_BLOCKING',
    description: 'Saves a spoken continuation note, architectural decision, or next-step action item directly to a specific Antigravity project dossier so Dr. Mohit can pick it up on his PC.',
    parameters: {
      type: 'OBJECT',
      properties: {
        project_name: {
          type: 'STRING',
          description: 'Name of the target Antigravity project.'
        },
        note: {
          type: 'STRING',
          description: 'Detailed continuation note or architectural instruction.'
        }
      },
      required: ['project_name', 'note']
    }
  }
];

async function getProjects(env) {
  if (!env.CARSPEAK_KV) return AG_PORTFOLIO_SEED;
  const raw = await env.CARSPEAK_KV.get('ag_projects_v1');
  if (!raw) {
    await env.CARSPEAK_KV.put('ag_projects_v1', JSON.stringify(AG_PORTFOLIO_SEED));
    return AG_PORTFOLIO_SEED;
  }
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) && parsed.length > 0 ? parsed : AG_PORTFOLIO_SEED;
  } catch {
    return AG_PORTFOLIO_SEED;
  }
}

async function getConversations(env) {
  if (!env.CARSPEAK_KV) return SEEDED_CONVERSATIONS;
  const raw = await env.CARSPEAK_KV.get('conversations_v1');
  if (!raw) {
    await env.CARSPEAK_KV.put('conversations_v1', JSON.stringify(SEEDED_CONVERSATIONS));
    return SEEDED_CONVERSATIONS;
  }
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) && parsed.length > 0 ? parsed : SEEDED_CONVERSATIONS;
  } catch {
    return SEEDED_CONVERSATIONS;
  }
}

async function saveConversations(env, list) {
  if (env.CARSPEAK_KV) {
    await env.CARSPEAK_KV.put('conversations_v1', JSON.stringify(list));
  }
}

function findMatchingProject(projects, query) {
  if (!query) return null;
  const q = query.toLowerCase().trim().replace(/[^a-z0-9]/g, '');
  return (
    projects.find(p => p.id.replace(/[^a-z0-9]/g, '') === q) ||
    projects.find(p => p.displayName.toLowerCase().replace(/[^a-z0-9]/g, '').includes(q)) ||
    projects.find(p => p.folderName.toLowerCase().replace(/[^a-z0-9]/g, '').includes(q)) ||
    projects.find(p => p.summary.toLowerCase().includes(query.toLowerCase().trim()))
  );
}

function findMatchingConversation(conversations, query) {
  if (!query) return conversations[0] || null;
  const q = query.toLowerCase().trim();
  const qClean = q.replace(/[^a-z0-9]/g, '');
  return (
    conversations.find(c => c.id.toLowerCase() === q) ||
    conversations.find(c => c.title.toLowerCase().replace(/[^a-z0-9]/g, '').includes(qClean)) ||
    conversations.find(c => (c.projectName || '').toLowerCase().replace(/[^a-z0-9]/g, '').includes(qClean)) ||
    conversations.find(c => (c.summary || '').toLowerCase().includes(q))
  );
}

async function executeVoiceTool(env, name, args = {}) {
  const projects = await getProjects(env);
  const conversations = await getConversations(env);

  if (name === 'list_archived_conversations') {
    const q = (args.query || '').toLowerCase().trim();
    const filtered = q
      ? conversations.filter(
          c =>
            c.title.toLowerCase().includes(q) ||
            (c.projectName || '').toLowerCase().includes(q) ||
            (c.summary || '').toLowerCase().includes(q)
        )
      : conversations;
    return {
      status: 'ok',
      totalCount: filtered.length,
      conversations: filtered.slice(0, 8).map(c => ({
        id: c.id,
        title: c.title,
        projectName: c.projectName || 'General',
        updatedAt: c.updatedAt,
        summary: c.summary,
        turnCount: (c.turns || []).length
      }))
    };
  }

  if (name === 'switch_to_conversation') {
    const target = findMatchingConversation(conversations, args.target_query);
    if (!target) {
      return {
        status: 'not_found',
        message: `No archived conversation matched "${args.target_query}". Available threads: ${conversations.slice(0, 5).map(c => c.title).join('; ')}`
      };
    }
    if (env.CARSPEAK_KV) {
      await env.CARSPEAK_KV.put('active_conversation_id', target.id);
    }
    return {
      status: 'switched',
      switchedConversation: target,
      instruction: `Immediately resume conversation "${target.title}". Briefly remind Dr. Mohit where you left off: ${target.summary}`
    };
  }

  if (name === 'start_new_conversation') {
    const matchedProj = args.project_name ? findMatchingProject(projects, args.project_name) : null;
    const newConv = {
      id: 'conv-' + Date.now(),
      title: args.title || (matchedProj ? `${matchedProj.displayName} Commute Session` : 'New Commute Session'),
      projectId: matchedProj ? matchedProj.id : '',
      projectName: matchedProj ? matchedProj.displayName : (args.project_name || 'General'),
      persona: 'executive',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      summary: matchedProj
        ? `Started new conversation anchored on ${matchedProj.displayName}: ${matchedProj.summary}`
        : `Started new conversation: ${args.title}`,
      turns: []
    };
    conversations.unshift(newConv);
    await saveConversations(env, conversations);
    if (env.CARSPEAK_KV) {
      await env.CARSPEAK_KV.put('active_conversation_id', newConv.id);
    }
    return {
      status: 'created_and_switched',
      newConversation: newConv,
      projectDossier: matchedProj
    };
  }

  if (name === 'get_ag_project_dossier') {
    const proj = findMatchingProject(projects, args.project_name);
    if (!proj) {
      return {
        status: 'not_found',
        message: `Could not find an exact match for "${args.project_name}". Closest categories include Neurosurgery (Radix, DuralGuard, PJKPredict, Spine-Measure, VigilOR), Medicolegal/Coding (MDEsq, JurisShield, CPTArmor), Finance (Futurus, LearnLab, ETF-Rebalancer), and Commute/AI (ScreenDrop, SnapEdge, Hands-Free Lingo, Vocalis).`
      };
    }
    const relatedThreads = conversations
      .filter(c => c.projectId === proj.id || (c.projectName || '').toLowerCase().includes(proj.folderName.toLowerCase()))
      .map(c => ({ id: c.id, title: c.title, summary: c.summary, updatedAt: c.updatedAt }));
    return {
      status: 'ok',
      project: proj,
      relatedConversations: relatedThreads
    };
  }

  if (name === 'save_ag_project_roadmap_note') {
    const proj = findMatchingProject(projects, args.project_name);
    const noteEntry = {
      id: 'note-' + Date.now(),
      note: args.note,
      timestamp: new Date().toISOString()
    };
    if (proj) {
      proj.roadmapNotes = proj.roadmapNotes || [];
      proj.roadmapNotes.unshift(noteEntry);
      if (env.CARSPEAK_KV) {
        await env.CARSPEAK_KV.put('ag_projects_v1', JSON.stringify(projects));
      }
      return {
        status: 'saved',
        project: proj.displayName,
        savedNote: noteEntry
      };
    }
    return {
      status: 'saved_general',
      project: args.project_name || 'General AG Inbox',
      savedNote: noteEntry
    };
  }

  return { status: 'unknown_tool', name };
}

function buildSystemInstruction(personaKey, projects, activeConv, conversations) {
  const basePersona = PERSONA_PROMPTS[personaKey] || PERSONA_PROMPTS.executive;
  const portfolioDigest = projects
    .slice(0, 48)
    .map(p => `• ${p.displayName} [${p.category}]: ${p.summary} (Focus: ${p.recentFocus})`)
    .join('\n');

  const archiveDigest = conversations
    .slice(0, 10)
    .map(c => `• [${c.id}] "${c.title}" (${c.projectName || 'General'}) — ${c.summary}`)
    .join('\n');

  let activeThreadBlock = '';
  if (activeConv) {
    const recentTurns = (activeConv.turns || [])
      .slice(-8)
      .map(t => `${t.role === 'user' ? 'Dr. Mohit' : 'CarSpeak'}: ${t.text}`)
      .join('\n');
    activeThreadBlock = `
ACTIVE CONVERSATION THREAD:
Title: "${activeConv.title}" (ID: ${activeConv.id}, Linked Project: ${activeConv.projectName || 'General'})
Summary: ${activeConv.summary}
Recent Transcript History:
${recentTurns || '(New thread — no prior turns yet)'}
`;
  }

  return `${basePersona}

VOICE COMMAND & ARCHIVE CAPABILITIES:
1. Dr. Mohit can ask you via voice at any time to list previous conversations, switch to a specific archived conversation, start a new conversation, or inspect/update any of his Antigravity (AG) projects.
2. Always invoke the matching tool (list_archived_conversations, switch_to_conversation, start_new_conversation, get_ag_project_dossier, save_ag_project_roadmap_note) immediately when he asks about a prior conversation or an Antigravity project.
3. When switching conversations, confirm the switch aloud in 1-2 sentences and summarize the last point so he can pick up right where he left off hands-free.

${activeThreadBlock}

ARCHIVED CONVERSATIONS AVAILABLE TO SWITCH TO:
${archiveDigest}

DR. MOHIT'S ANTIGRAVITY (AG) PROJECT PORTFOLIO (${projects.length} APPLICATIONS DEVELOPED):
${portfolioDigest}`;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    try {
      // 1. Health & Pre-Flight Endpoint
      if (url.pathname === '/api/health') {
        const projects = await getProjects(env);
        const conversations = await getConversations(env);
        return Response.json(
          {
            status: 'ok',
            app: 'CarSpeak',
            bundleId: 'com.AlexMohit.CarSpeak',
            liveModel: 'gemini-3.8-live',
            fallbackModel: 'gemini-2.5-flash',
            hasApiKey: Boolean(env.GEMINI_API_KEY),
            agProjectCount: projects.length,
            archivedConversationCount: conversations.length,
            transportFeatures: [
              '5s-Circular-PCM16-Outbox-RingBuffer',
              'Gemini-3.8-Live-SessionResumptionConfig',
              'SlidingWindow-ContextCompression',
              'NWPathMonitor-Sub250ms-5G-Handoff',
              'CarPlay-VoiceBasedConversation-And-AppIntents'
            ],
            timestamp: new Date().toISOString()
          },
          { headers: CORS_HEADERS }
        );
      }

      // 2. Antigravity Projects Portfolio API
      if (url.pathname === '/api/projects' && request.method === 'GET') {
        const projects = await getProjects(env);
        const q = url.searchParams.get('q');
        if (q) {
          const match = findMatchingProject(projects, q);
          return Response.json({ status: 'ok', match, total: projects.length }, { headers: CORS_HEADERS });
        }
        return Response.json({ status: 'ok', count: projects.length, projects }, { headers: CORS_HEADERS });
      }

      if (url.pathname === '/api/projects/sync' && request.method === 'POST') {
        const body = await request.json();
        if (Array.isArray(body.projects) && env.CARSPEAK_KV) {
          await env.CARSPEAK_KV.put('ag_projects_v1', JSON.stringify(body.projects));
          return Response.json({ status: 'synced', count: body.projects.length }, { headers: CORS_HEADERS });
        }
        return Response.json({ error: 'Invalid projects payload' }, { status: 400, headers: CORS_HEADERS });
      }

      // 3. Archived Conversations Vault API
      if (url.pathname === '/api/conversations' && request.method === 'GET') {
        const conversations = await getConversations(env);
        const activeId = (env.CARSPEAK_KV && (await env.CARSPEAK_KV.get('active_conversation_id'))) || conversations[0]?.id;
        return Response.json({ status: 'ok', activeConversationId: activeId, conversations }, { headers: CORS_HEADERS });
      }

      if (url.pathname === '/api/conversations' && request.method === 'POST') {
        const body = await request.json();
        const conversations = await getConversations(env);
        const projects = await getProjects(env);

        if (body.action === 'append_turn') {
          let conv = conversations.find(c => c.id === body.conversationId) || conversations[0];
          if (!conv) {
            conv = {
              id: body.conversationId || 'conv-' + Date.now(),
              title: body.title || 'Commute Session',
              projectId: '',
              projectName: 'General',
              persona: body.persona || 'executive',
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString(),
              summary: '',
              turns: []
            };
            conversations.unshift(conv);
          }
          if (body.userText) {
            conv.turns.push({ role: 'user', text: body.userText, timestamp: new Date().toISOString() });
          }
          if (body.modelText) {
            conv.turns.push({ role: 'model', text: body.modelText, timestamp: new Date().toISOString() });
            conv.summary = body.modelText.slice(0, 220);
          }
          // Auto-detect referenced AG project if not yet linked
          if ((!conv.projectId || conv.projectName === 'General') && body.userText) {
            const detected = projects.find(p =>
              body.userText.toLowerCase().includes(p.folderName.toLowerCase()) ||
              body.userText.toLowerCase().includes(p.displayName.toLowerCase().split(' ')[0])
            );
            if (detected) {
              conv.projectId = detected.id;
              conv.projectName = detected.displayName;
              if (conv.title === 'Commute Session' || conv.title === 'New Commute Session') {
                conv.title = `${detected.displayName} Commute Discussion`;
              }
            }
          }
          conv.updatedAt = new Date().toISOString();
          await saveConversations(env, conversations);
          return Response.json({ status: 'saved', conversation: conv }, { headers: CORS_HEADERS });
        }

        if (body.action === 'create') {
          const result = await executeVoiceTool(env, 'start_new_conversation', {
            title: body.title || 'New Commute Session',
            project_name: body.projectName || ''
          });
          return Response.json(result, { headers: CORS_HEADERS });
        }

        if (body.action === 'switch') {
          const result = await executeVoiceTool(env, 'switch_to_conversation', {
            target_query: body.targetQuery || body.conversationId
          });
          return Response.json(result, { headers: CORS_HEADERS });
        }

        return Response.json({ error: 'Unknown conversation action' }, { status: 400, headers: CORS_HEADERS });
      }

      // 4. Non-Blocking Voice Tool Execution Endpoint (Called by iOS GeminiLiveSessionManager during Live WebSocket)
      if (url.pathname === '/api/tool-call' && request.method === 'POST') {
        const { name, args } = await request.json();
        const result = await executeVoiceTool(env, name, args || {});
        return Response.json({ status: 'ok', name, result }, { headers: CORS_HEADERS });
      }

      // 5. Gemini 3.8 Live Session Provisioning Endpoint
      if (url.pathname === '/api/live-session' && (request.method === 'POST' || request.method === 'GET')) {
        if (!env.GEMINI_API_KEY) {
          return Response.json({ error: 'GEMINI_API_KEY secret not configured' }, { status: 500, headers: CORS_HEADERS });
        }
        let body = {};
        if (request.method === 'POST') {
          try { body = await request.json(); } catch {}
        }
        const persona = body.persona || 'executive';
        const projects = await getProjects(env);
        const conversations = await getConversations(env);
        const activeId =
          body.conversationId ||
          (env.CARSPEAK_KV && (await env.CARSPEAK_KV.get('active_conversation_id'))) ||
          conversations[0]?.id;
        const activeConv = conversations.find(c => c.id === activeId) || conversations[0];
        const systemInstruction = buildSystemInstruction(persona, projects, activeConv, conversations);

        const wsUrl = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${env.GEMINI_API_KEY}`;

        const setupPayload = {
          setup: {
            model: 'models/gemini-3.8-live',
            generationConfig: {
              responseModalities: ['AUDIO'],
              speechConfig: {
                voiceConfig: {
                  prebuiltVoiceConfig: {
                    voiceName: body.voiceName || 'Puck'
                  }
                }
              }
            },
            systemInstruction: {
              parts: [{ text: systemInstruction }]
            },
            tools: [
              {
                functionDeclarations: LIVE_VOICE_TOOLS
              }
            ],
            sessionResumption: body.resumptionHandle ? { handle: body.resumptionHandle } : {},
            contextWindowCompression: {
              slidingWindow: {},
              triggerTokens: 32000
            },
            inputAudioTranscription: {},
            outputAudioTranscription: {}
          }
        };

        return Response.json(
          {
            status: 'ok',
            wsUrl,
            model: 'models/gemini-3.8-live',
            activeConversation: activeConv,
            setupPayload,
            tools: LIVE_VOICE_TOOLS
          },
          { headers: CORS_HEADERS }
        );
      }

      // 6. Resilient Voice/Text Turn Endpoint (/api/chat) with Deterministic Edge Tool Execution + Gemini Inference
      if (url.pathname === '/api/chat' && request.method === 'POST') {
        const body = await request.json();
        const userMessage = (body.message || '').trim();
        if (!userMessage) {
          return Response.json({ error: 'Empty message' }, { status: 400, headers: CORS_HEADERS });
        }

        const persona = body.persona || 'executive';
        const projects = await getProjects(env);
        let conversations = await getConversations(env);
        let activeId =
          body.conversationId ||
          (env.CARSPEAK_KV && (await env.CARSPEAK_KV.get('active_conversation_id'))) ||
          conversations[0]?.id;
        let activeConv = conversations.find(c => c.id === activeId) || conversations[0];

        const executedTools = [];
        let deterministicReply = '';
        const lowerMsg = userMessage.toLowerCase();

        // A. Deterministic Voice Intent Detection for <10ms CarPlay Edge Execution
        if (lowerMsg.includes('switch to') || lowerMsg.includes('go back to') || lowerMsg.includes('resume our conversation')) {
          const cleaned = userMessage
            .replace(/^(please\s+)?(switch to|go back to|resume)\s+(our\s+|my\s+)?(previous\s+)?(conversation\s+|thread\s+)?(on|about)?\s*/i, '')
            .split(/\s+and\s+/i)[0]
            .trim();
          const toolResult = await executeVoiceTool(env, 'switch_to_conversation', { target_query: cleaned || userMessage });
          executedTools.push({ name: 'switch_to_conversation', args: { target_query: cleaned }, result: toolResult });
          if (toolResult.switchedConversation) {
            activeConv = toolResult.switchedConversation;
            activeId = activeConv.id;
            deterministicReply = `Switched to your "${activeConv.title}" conversation (${activeConv.projectName || 'General'}). Where we left off: ${activeConv.summary}`;
          } else {
            deterministicReply = toolResult.message;
          }
        } else if (lowerMsg.includes('list') && (lowerMsg.includes('conversation') || lowerMsg.includes('archive') || lowerMsg.includes('thread'))) {
          const toolResult = await executeVoiceTool(env, 'list_archived_conversations', { query: '' });
          executedTools.push({ name: 'list_archived_conversations', args: {}, result: toolResult });
          const titles = (toolResult.conversations || []).map((c, idx) => `${idx + 1}) ${c.title} (${c.projectName})`).join('; ');
          deterministicReply = `You have ${toolResult.totalCount} archived conversations in CarSpeak: ${titles}. Say "Switch to" followed by any topic or project name to jump right in.`;
        } else if (lowerMsg.includes('start a new conversation') || lowerMsg.includes('new thread')) {
          const titleMatch = userMessage.replace(/.*(titled|about|on)\s+/i, '').trim() || 'New Commute Session';
          const toolResult = await executeVoiceTool(env, 'start_new_conversation', { title: titleMatch, project_name: titleMatch });
          executedTools.push({ name: 'start_new_conversation', args: { title: titleMatch }, result: toolResult });
          if (toolResult.newConversation) {
            activeConv = toolResult.newConversation;
            activeId = activeConv.id;
            deterministicReply = `Archived your previous thread and started a new conversation: "${activeConv.title}". Ready whenever you are.`;
          }
        } else if (lowerMsg.includes('save a note') || lowerMsg.includes('log an action item') || lowerMsg.includes('roadmap note')) {
          const matchedProj = projects.find(p =>
            lowerMsg.includes(p.folderName.toLowerCase()) ||
            lowerMsg.includes(p.displayName.toLowerCase().split(' ')[0])
          );
          const projName = matchedProj ? matchedProj.displayName : (activeConv?.projectName || 'CarSpeak');
          const toolResult = await executeVoiceTool(env, 'save_ag_project_roadmap_note', {
            project_name: projName,
            note: userMessage
          });
          executedTools.push({ name: 'save_ag_project_roadmap_note', args: { project_name: projName, note: userMessage }, result: toolResult });
          deterministicReply = `Saved that roadmap action item directly to your ${projName} dossier in the Antigravity vault.`;
        }

        // Also check if the user referenced any of the 56 Antigravity projects directly
        const referencedProjects = projects.filter(p => {
          const fn = p.folderName.toLowerCase().replace(/[^a-z0-9]/g, '');
          const dn = p.displayName.toLowerCase().split(' ')[0].replace(/[^a-z0-9]/g, '');
          const msgClean = lowerMsg.replace(/[^a-z0-9]/g, '');
          return (fn.length >= 4 && msgClean.includes(fn)) || (dn.length >= 4 && msgClean.includes(dn));
        });

        for (const rp of referencedProjects.slice(0, 2)) {
          const dossierRes = await executeVoiceTool(env, 'get_ag_project_dossier', { project_name: rp.displayName });
          executedTools.push({ name: 'get_ag_project_dossier', args: { project_name: rp.displayName }, result: dossierRes });
        }

        // B. Attempt Gemini Upstream Inference (if active API key is valid)
        let replyText = '';
        const apiKey = request.headers.get('X-Gemini-Key') || env.GEMINI_API_KEY;
        if (apiKey) {
          try {
            const systemInstruction = buildSystemInstruction(persona, projects, activeConv, conversations);
            const contents = [];
            for (const t of (activeConv?.turns || []).slice(-8)) {
              contents.push({
                role: t.role === 'model' ? 'model' : 'user',
                parts: [{ text: t.text }]
              });
            }
            const contextPrefix = executedTools.length > 0
              ? `[Executed Voice Tools: ${JSON.stringify(executedTools)}]\nUser Spoken Input: ${userMessage}`
              : userMessage;
            contents.push({ role: 'user', parts: [{ text: contextPrefix }] });

            const geminiUrl = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
            const geminiResp = await fetch(geminiUrl, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                systemInstruction: { parts: [{ text: systemInstruction }] },
                contents,
                generationConfig: { temperature: 0.4, maxOutputTokens: 600 }
              })
            });
            if (geminiResp.ok) {
              const geminiData = await geminiResp.json();
              const parts = geminiData?.candidates?.[0]?.content?.parts || [];
              replyText = parts.map(p => p.text || '').join(' ').trim();
            }
          } catch {}
        }

        // C. Synthesize Rich Spoken Response from Edge Graph if Upstream Key not yet rotated
        if (!replyText) {
          if (deterministicReply && referencedProjects.length > 0) {
            const projDetails = referencedProjects
              .slice(0, 2)
              .map(p => `${p.displayName} (${p.category}): ${p.summary} Recent focus: ${p.recentFocus}`)
              .join(' | ');
            replyText = `${deterministicReply} Active Project Context — ${projDetails}`;
          } else if (deterministicReply) {
            replyText = deterministicReply;
          } else if (referencedProjects.length > 0) {
            const projDetails = referencedProjects
              .slice(0, 3)
              .map(p => `${p.displayName} [${p.category}]: ${p.summary} Current focus: ${p.recentFocus}`)
              .join(' ');
            replyText = `Here is where we left off on ${referencedProjects.map(p => p.displayName).join(' and ')}: ${projDetails}`;
          } else if (activeConv) {
            replyText = `In your active "${activeConv.title}" thread (${activeConv.projectName || 'General'}), our focus is: ${activeConv.summary} You can ask me to switch to any archived conversation or reference any of your ${projects.length} Antigravity projects hands-free.`;
          }
        }

        // Persist turn in the active conversation archive
        conversations = await getConversations(env);
        let targetConv = conversations.find(c => c.id === activeId) || conversations[0];
        if (targetConv) {
          targetConv.turns = targetConv.turns || [];
          targetConv.turns.push({ role: 'user', text: userMessage, timestamp: new Date().toISOString() });
          targetConv.turns.push({ role: 'model', text: replyText, timestamp: new Date().toISOString() });
          targetConv.summary = replyText.slice(0, 240);
          targetConv.updatedAt = new Date().toISOString();
          await saveConversations(env, conversations);
        }

        return Response.json(
          {
            status: 'ok',
            reply: replyText,
            activeConversation: targetConv,
            executedTools
          },
          { headers: CORS_HEADERS }
        );
      }

      if (env.ASSETS) {
        return env.ASSETS.fetch(request);
      }

      return Response.json({ status: 'CarSpeak Edge Worker Online' }, { headers: CORS_HEADERS });
    } catch (err) {
      return Response.json({ error: err.message || String(err) }, { status: 500, headers: CORS_HEADERS });
    }
  }
};
