const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onVoteWrite = functions.firestore
  .document("pairs/{pairId}/votes/{voteId}")
  .onWrite(async (change, context) => {
    const { pairId } = context.params;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) {
      return null;
    }

    const titleId = after.titleId;
    if (!titleId) {
      return null;
    }

    const pairRef = admin.firestore().collection("pairs").doc(pairId);
    const pairSnap = await pairRef.get();
    if (!pairSnap.exists) {
      return null;
    }

    const { memberA, memberB } = pairSnap.data();
    if (!memberA || !memberB) {
      return null;
    }

    const votesRef = pairRef.collection("votes");
    const [voteA, voteB] = await Promise.all([
      votesRef.doc(`${titleId}_${memberA}`).get(),
      votesRef.doc(`${titleId}_${memberB}`).get(),
    ]);

    const likeA = voteA.exists && voteA.data().value === "like";
    const likeB = voteB.exists && voteB.data().value === "like";

    if (likeA && likeB) {
      const matchRef = pairRef.collection("matches").doc(titleId);
      await matchRef.set(
        {
          titleId,
          matchedAt: admin.firestore.FieldValue.serverTimestamp(),
          likedBy: [memberA, memberB],
        },
        { merge: true }
      );
    }

    return null;
  });
