const app = document.getElementById('app');
const voyantePanel = document.getElementById('voyante-panel');
const baronnePanel = document.getElementById('baronne-panel');
const schemaPrice = document.getElementById('schema-price');
const schemaCount = document.getElementById('schema-count');
const buyButton = document.getElementById('buy-schema');
const toast = document.getElementById('toast');
const voicePlayer = document.getElementById('voice-player');
const voiceHint = document.getElementById('voice-hint');
const voiceInstruction = document.getElementById('voice-instruction');

const voices = {
    voyante_intro: 'audio/voyante_intro.mp3',
    voyante_joueur_oui: 'audio/voyante_joueur_oui.mp3',
    voyante_joueur_non: 'audio/voyante_joueur_non.mp3',
    baronne_intro: 'audio/baronne_intro.mp3',
    baronne_achat_schema_sns: 'audio/baronne_achat_schema_sns.mp3',
    baronne_sans_achat: 'audio/baronne_sans_achat.mp3'
};

let activeVoiceId = null;
let toastTimer;

const resourceName = () => typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'fabrication_armes_shop';

async function nui(action, data = {}) {
    if (!window.invokeNative) return { ok: false, message: 'Aperçu navigateur : action indisponible.' };
    try {
        const response = await fetch(`https://${resourceName()}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        });
        return await response.json();
    } catch (_) {
        return { ok: false, message: 'Communication interrompue.' };
    }
}

function money(value) {
    return new Intl.NumberFormat('fr-FR').format(Number(value) || 0) + ' $';
}

function showToast(message, type = '') {
    clearTimeout(toastTimer);
    toast.textContent = message || 'Action impossible.';
    toast.className = `toast visible ${type}`;
    toastTimer = setTimeout(() => { toast.className = 'toast'; }, 3200);
}

function showPanel(panel) {
    voyantePanel.classList.toggle('hidden', panel !== 'voyante');
    baronnePanel.classList.toggle('hidden', panel !== 'baronne');
    app.classList.remove('hidden');
    app.setAttribute('aria-hidden', 'false');
}

function closeVisual() {
    app.classList.add('hidden');
    app.setAttribute('aria-hidden', 'true');
}

async function requestClose() {
    if (app.classList.contains('hidden')) return;
    closeVisual();
    await nui('close');
}

async function finishVoice(completed = false) {
    const id = activeVoiceId;
    activeVoiceId = null;
    voiceHint.classList.add('hidden');
    if (id !== null) await nui('audioFinished', { id, completed });
}

voicePlayer.addEventListener('ended', () => finishVoice(true));
voicePlayer.addEventListener('error', () => finishVoice(false));

document.getElementById('answer-yes').addEventListener('click', async () => {
    closeVisual();
    await nui('voyanteAnswer', { answer: 'yes' });
});

document.getElementById('answer-no').addEventListener('click', async () => {
    closeVisual();
    await nui('voyanteAnswer', { answer: 'no' });
});

buyButton.addEventListener('click', async () => {
    buyButton.disabled = true;
    const response = await nui('buySchema');
    if (response.ok) {
        closeVisual();
    } else {
        buyButton.disabled = false;
        showToast(response.message, 'error');
    }
});

document.getElementById('close-button').addEventListener('click', requestClose);
document.addEventListener('keydown', event => { if (event.key === 'Escape') requestClose(); });

window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'openVoyante') showPanel('voyante');
    if (data.action === 'openBaronne') {
        schemaPrice.textContent = money(data.economy && data.economy.schemaPrice);
        schemaCount.textContent = Number(data.schemaCount) || 0;
        buyButton.disabled = false;
        showPanel('baronne');
    }
    if (data.action === 'close') closeVisual();
    if (data.action === 'playVoice') {
        const source = voices[data.name];
        activeVoiceId = Number(data.id);
        if (!source) { finishVoice(false); return; }
        voicePlayer.pause();
        voicePlayer.currentTime = 0;
        voicePlayer.src = source;
        voicePlayer.volume = 1;
        voiceInstruction.textContent = data.skippable ? `[${data.skipLabel || 'ESPACE'}] Passer la voix` : 'Première écoute obligatoire';
        voiceHint.classList.remove('hidden');
        voicePlayer.play().catch(() => finishVoice(false));
    }
    if (data.action === 'stopVoice' && (data.id === undefined || Number(data.id) === activeVoiceId)) {
        activeVoiceId = null;
        voicePlayer.pause();
        voicePlayer.currentTime = 0;
        voiceHint.classList.add('hidden');
    }
    if (data.action === 'hideVoice' && (activeVoiceId === null || Number(data.id) === activeVoiceId)) {
        voiceHint.classList.add('hidden');
    }
});

// Aucun aperçu automatique : la NUI FiveM reste invisible au démarrage.
closeVisual();
