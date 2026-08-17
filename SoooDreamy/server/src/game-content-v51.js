// 5.1 Games Wave II content used by the authoritative relay.
// User-facing translations live in the Swift content pack; the server keeps
// only normalized dictionaries and the event contract behind weekly bingo.

function words(value) {
  return new Set(value.split(/\s+/u).map((word) => word.toLocaleLowerCase('de-DE')));
}

export const WORD_CHAIN_WORDS = Object.freeze({
  de: words(`
    abend abenteuer achtsamkeit anfang apfel arm band berg bild blume boot brief
    brücke buch café dach date danke diamant duft eis elefant engel erinnerung
    essen fahrrad familie feder feuer film fluss foto freude frühling fuß garten
    geborgenheit geschenk glück gold hand harmonika haus herz himmel humor insel
    jahrestag jahr kamera kerze kino kleeblatt koffer konzert kuss lachen lampe
    leben leuchtturm liebe lied luft meer mensch moment mond morgen musik mut
    nacht nähe nest oase ort partner pause picknick planet platz puzzle regen
    reise ring roman rose schatz schokolade see sonne sonnenblume spiel stern
    strand tag tandem tanz tasse team theater traum tür ufer umarmung urlaub
    vertrauen vogel wärme wasser weg welt wiese wolke wort wunsch zeit zelt ziel
    zuhause zukunft maßfuß
  `),
  en: words(`
    adventure affection apple arm beach beginning bicycle bird blanket blossom
    boat book bridge candle camera care chocolate cinema cloud coffee concert
    courage dance date day delight diamond dream evening family feather fire
    flower forest friend future garden gift glow gold hand harmony heart holiday
    home hope hug humor island journey joy kindness kiss lake lamp laughter letter
    lighthouse love luck memory moment moon morning movie music night ocean park
    partner pause picnic place planet promise puzzle rain rainbow river road rose
    sea smile song sparkle star story summer sun surprise team theater time
    together touch travel tree trust umbrella vacation warmth water way wish word
    world year yesterday zest
  `),
});

// Sixty curated micro-action templates. A weekly 4x4 board chooses sixteen
// different event types, so one validated app event can check at most one tile.
export const BINGO_ACTIONS = Object.freeze([
  ['heartbeat', 'thanks_sent'], ['compliment', 'thanks_sent'],
  ['miss_you', 'missyou_sent'], ['tiny_thanks', 'thanks_sent'],
  ['open_capsule', 'capsule_opened'], ['seal_capsule', 'capsule_sealed'],
  ['share_need', 'need_sent'], ['create_goal', 'goal_created'],
  ['goal_step', 'goal_milestone'], ['finish_goal', 'goal_reached'],
  ['plan_time', 'weekplan_slot_created'], ['read_magazine', 'magazine_seen_both'],
  ['movie_match', 'movie_match'], ['daily_quest', 'quest_done'],
  ['gift_icon', 'icon_gift_sent'], ['plan_date', 'datenight_planned'],
  ['three_good_things', 'goodthings_both'], ['confirm_inside_word', 'dictionary_confirmed'],
  ['log_first', 'first_logged'], ['make_calendar', 'season_calendar_created'],
  ['open_door', 'season_calendar_door_opened'], ['kind_message', 'thanks_sent'],
  ['warm_ping', 'missyou_sent'], ['listen_need', 'need_sent'],
  ['dream_goal', 'goal_created'], ['quarter_goal', 'goal_milestone'],
  ['shared_win', 'goal_reached'], ['call_slot', 'weekplan_slot_created'],
  ['month_memory', 'magazine_seen_both'], ['pick_film', 'movie_match'],
  ['quest_together', 'quest_done'], ['surprise_icon', 'icon_gift_sent'],
  ['date_night', 'datenight_planned'], ['gratitude_evening', 'goodthings_both'],
  ['our_word', 'dictionary_confirmed'], ['first_memory', 'first_logged'],
  ['countdown', 'season_calendar_created'], ['door_surprise', 'season_calendar_door_opened'],
  ['say_thanks', 'thanks_sent'], ['thinking_of_you', 'missyou_sent'],
  ['ask_gently', 'need_sent'], ['shared_plan', 'goal_created'],
  ['celebrate_progress', 'goal_milestone'], ['goal_confetti', 'goal_reached'],
  ['reserve_evening', 'weekplan_slot_created'], ['read_together', 'magazine_seen_both'],
  ['film_evening', 'movie_match'], ['micro_quest', 'quest_done'],
  ['icon_present', 'icon_gift_sent'], ['countdown_date', 'datenight_planned'],
  ['three_bright_spots', 'goodthings_both'], ['inside_joke', 'dictionary_confirmed'],
  ['remember_beginning', 'first_logged'], ['calendar_for_you', 'season_calendar_created'],
  ['unwrap_door', 'season_calendar_door_opened'], ['specific_praise', 'thanks_sent'],
  ['distance_hug', 'missyou_sent'], ['make_space', 'need_sent'],
  ['next_adventure', 'goal_created'], ['small_milestone', 'goal_milestone'],
].map(([id, eventType], index) => Object.freeze({ index, id, eventType })));

export function bingoCardIndexes(seed, count = 16) {
  // SplitMix64-compatible deterministic shuffle kept local to avoid exporting
  // the game-rule implementation. De-duplicate event types on a board.
  let state = BigInt.asUintN(64, BigInt(seed));
  const next = (bound) => {
    state = BigInt.asUintN(64, state + 0x9e3779b97f4a7c15n);
    let value = state;
    value = BigInt.asUintN(64, (value ^ (value >> 30n)) * 0xbf58476d1ce4e5b9n);
    value = BigInt.asUintN(64, (value ^ (value >> 27n)) * 0x94d049bb133111ebn);
    value ^= value >> 31n;
    return Number(BigInt.asUintN(64, value) % BigInt(bound));
  };
  const shuffled = BINGO_ACTIONS.map((action) => action.index);
  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const other = next(index + 1);
    [shuffled[index], shuffled[other]] = [shuffled[other], shuffled[index]];
  }
  const eventTypes = new Set();
  const result = [];
  for (const index of shuffled) {
    const eventType = BINGO_ACTIONS[index].eventType;
    if (eventTypes.has(eventType)) continue;
    eventTypes.add(eventType);
    result.push(index);
    if (result.length === count) break;
  }
  return result;
}
