-- Seed for the Gifts catalog (migrations 0022 + 0023): the real handmade-art
-- catalog. Replaces the Pexels placeholders that were here first.
--
-- These are hand-painted lippan (mirror-work) pieces by a single artisan seller:
-- devotional plates, mandalas, wall mirrors, tasselled hangings, a key holder.
-- Every product carries a gallery (image_urls) - the full piece plus close-ups -
-- with the first image doubling as the card thumbnail (image_url). Photos are the
-- seller's own originals, uploaded to our Cloudinary CDN (cloud mqppsahn) through
-- the app's unsigned preset.
--
-- PLACEHOLDERS, to be replaced when the seller confirms:
--   * every price is 999
--   * the shop name / tagline / blurb on gs1
--
-- Idempotent: clears the gifts tables first, so re-running rebuilds the catalog
-- rather than colliding on ids.

delete from public.gift_items;
delete from public.gift_shops;

insert into public.gift_shops
  (id, name, tagline, description, image_url, rating, rating_count)
values
  ('gs1', 'Handmade Art Studio',
   'Hand-painted lippan and mirror-work art',
   'One-of-a-kind handcrafted wall art - mandalas, devotional plates, mirrors and tasselled hangings, each piece painted and mirrored by hand.',
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654610/zopiqnow/em2h5onajtbqy2xqfd1e.jpg',
   null, 0);

insert into public.gift_items
  (id, shop_id, name, description, price, image_url, image_urls,
   category, category_rank, item_rank)
values
  ('gs1-evil-eye-hanging', 'gs1',
   'Evil Eye Mandala Wall Hanging',
   'Hand-painted mandala disc in fine mirror work, finished with beaded cotton tassels. The evil eye motif is traditionally hung at an entrance to keep a home safe.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784653811/zopiqnow/oj3d3qousan2uw4g7j5o.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653811/zopiqnow/oj3d3qousan2uw4g7j5o.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653844/zopiqnow/ypszuvqoqjs3mfsfpmnh.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653854/zopiqnow/wtfrufj3fspayvlapbih.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653871/zopiqnow/rhk6yirbgruwcviktcr7.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653888/zopiqnow/grkimgam4mlfded5i6vn.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653911/zopiqnow/ydyr3noyfwgzbxc6xkdn.jpg'
   ],
   'Wall Hangings', 3, 0),
  ('gs1-kamdhenu-cow', 'gs1',
   'Kamdhenu Cow Lippan Wall Plate',
   'A circular wall plate in lippan mirror work - the sacred cow framed by lotuses on a marigold ground. Entirely handmade, so no two are alike.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784653935/zopiqnow/j80sq14zgu5ysvrqubtf.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653935/zopiqnow/j80sq14zgu5ysvrqubtf.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653955/zopiqnow/i5qvc82iaijvq276ao5y.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784653980/zopiqnow/qns0oeiqa5r1qxo8qrp0.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654006/zopiqnow/nilbs1mrr6bd8obupnuj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654018/zopiqnow/dwlacc1zxeewsu1jwzdh.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654032/zopiqnow/szmyonshssqia34dr02w.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654043/zopiqnow/rwll3yqeaxpkczoa1vnk.jpg'
   ],
   'Devotional Art', 0, 0),
  ('gs1-shivling', 'gs1',
   'Shivling Lippan Wall Plate',
   'The Shivling framed by a lotus and a ring of painted petals, finished with mirror inlay. A calm, devotional piece for a mandir wall.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654061/zopiqnow/bitqc0hbjc5k7kojbzro.png',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654061/zopiqnow/bitqc0hbjc5k7kojbzro.png',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654073/zopiqnow/trzybgwahm4y30xaortn.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654083/zopiqnow/mvzmz7uwn5zkjmwcjakp.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654095/zopiqnow/htwzsibbwwztbmnyanye.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654104/zopiqnow/whwlrjhxdrpvkryssltb.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654116/zopiqnow/btccvyazn7botbxmqvn4.jpg'
   ],
   'Devotional Art', 0, 1),
  ('gs1-peacock-key-holder', 'gs1',
   'Peacock Lippan Key Holder',
   'A half-moon key holder with a peacock in full display, mirror-inlaid feathers and five sturdy hooks. Useful and beautiful by the front door.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654141/zopiqnow/u0jcrvlmb2wazdx4pe3q.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654141/zopiqnow/u0jcrvlmb2wazdx4pe3q.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654157/zopiqnow/kua0wh1kgr1ow8k2tbnx.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654169/zopiqnow/sqo1wxddgptpvx8pm1kr.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654191/zopiqnow/r6tq0snmal31t1masrwa.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654226/zopiqnow/ziwdvox432idiajo2kaj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654233/zopiqnow/ffw3pv0ts9rmp2i5vqfh.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654239/zopiqnow/ox3672lk8a1uh775li4n.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654245/zopiqnow/okov9hhw6yjq86wgqvar.jpg'
   ],
   'Key Holders', 4, 0),
  ('gs1-blue-lotus-frame', 'gs1',
   'Blue Lotus Mandala Wall Frame',
   'A square frame carrying a layered blue lotus mandala in cut mirror work, bordered in deep indigo. Reads beautifully against a plain wall.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654280/zopiqnow/zatmw7vr768vbub6gyb5.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654280/zopiqnow/zatmw7vr768vbub6gyb5.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654314/zopiqnow/xjcnhs3jydv6wo3scube.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654325/zopiqnow/y1fix4cs2cs9aiftciwa.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654348/zopiqnow/bxdnpempl00fdsvldmtl.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654363/zopiqnow/wyhwa6n5m3pcayuim642.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654371/zopiqnow/kjjmjkmctuyvnlurtzf3.jpg'
   ],
   'Mandala and Lotus', 1, 0),
  ('gs1-yellow-floral-mirror', 'gs1',
   'Yellow Floral Lippan Wall Mirror',
   'A round wall mirror ringed with hand-painted pink and white blooms on a sunny yellow ground, set with mirror chips.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654388/zopiqnow/lw9wwrz4uhwypgfs7uxc.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654388/zopiqnow/lw9wwrz4uhwypgfs7uxc.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654405/zopiqnow/ptzuwtsmyokwgt1onziv.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654434/zopiqnow/zed7nuxriodistic1vku.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654444/zopiqnow/dfor7vtjj5ex4wkzozhf.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654453/zopiqnow/sicrozccskhiyyzesufy.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654519/zopiqnow/tltfgkzw4mz7ul5hykj1.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654527/zopiqnow/efw7mgryjtpipbjqzsbr.jpg'
   ],
   'Wall Mirrors', 2, 0),
  ('gs1-ivory-mirror', 'gs1',
   'Ivory Lippan Wall Mirror',
   'A round wall mirror in ivory and white, textured with rows of tiny mirrors and a diamond border. Quiet enough for any room.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654538/zopiqnow/hgf6k5rtah7wtku03rpz.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654538/zopiqnow/hgf6k5rtah7wtku03rpz.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654551/zopiqnow/ojrrclaamxnvnlbgight.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654563/zopiqnow/v7c7dsymspxmuoa9qrog.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654567/zopiqnow/czkuuetn7hyd0jw46rzf.jpg'
   ],
   'Wall Mirrors', 2, 1),
  ('gs1-rose-mandala', 'gs1',
   'Rose Pink Mandala Lippan Wall Art',
   'A large mandala in soft rose pink, layered ring upon ring with mirror inlay and fine relief work. A statement piece.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654610/zopiqnow/em2h5onajtbqy2xqfd1e.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654610/zopiqnow/em2h5onajtbqy2xqfd1e.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654622/zopiqnow/xcoiuaepkpkdonpueafp.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654645/zopiqnow/sfcemd8axmdakn67t7ot.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654666/zopiqnow/a3frlzc79wy9jkq6wcw9.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654678/zopiqnow/oolhwgq3hazyma48sshd.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654690/zopiqnow/o2xxighryof5xuvic086.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654705/zopiqnow/tpihsggxsmn4dtp1bdr1.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654715/zopiqnow/nv8yi45za4o3cjasbtua.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654723/zopiqnow/mghwhhtuym1fgc5fyhyg.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654733/zopiqnow/vozow8iisvyimatq0rvp.jpg'
   ],
   'Mandala and Lotus', 1, 1),
  ('gs1-sita-ram', 'gs1',
   'Sita Ram Naam Lippan Wall Plate',
   'The Sita Ram naam at the centre of a red and gold mandala, ringed with mirror work and fine stone detailing.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654743/zopiqnow/wf2dphkfhi8vukur18oa.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654743/zopiqnow/wf2dphkfhi8vukur18oa.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654754/zopiqnow/fkoc4xfuzvnt73xtkovd.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654764/zopiqnow/ciq76fbug0zqfkaxpfih.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654774/zopiqnow/phzxir1ni8p0eytaiarz.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654785/zopiqnow/zcgorsw82suefshfnzqh.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654795/zopiqnow/rfs1bk7auxcpol4kme3f.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654799/zopiqnow/ulxwybuypeowfmqlogux.jpg'
   ],
   'Devotional Art', 0, 2),
  ('gs1-radha-naam', 'gs1',
   'Radha Naam Lippan Wall Plate',
   'The Radha naam in gold, set on deep teal and framed by rings of yellow petals and mirror inlay.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654808/zopiqnow/ttbcxnxoj4utwmedmwfj.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654808/zopiqnow/ttbcxnxoj4utwmedmwfj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654836/zopiqnow/ty4ukyuhjgvona0zr0fm.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654846/zopiqnow/jxijsuia0sslhedfgtng.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654860/zopiqnow/keboukttievwpzgtiox8.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654870/zopiqnow/texwcriykcuyzulgtbpe.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654886/zopiqnow/v82ewaq8oxdyr8fjok6k.jpg'
   ],
   'Devotional Art', 0, 3),
  ('gs1-shri-charan', 'gs1',
   'Shri Charan Lippan Wall Plate',
   'The divine charan - the holy footprints - painted in red on a warm ochre plate, circled with mirror work.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784654905/zopiqnow/buzjdipoyiwaz6wpfd7n.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654905/zopiqnow/buzjdipoyiwaz6wpfd7n.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654923/zopiqnow/cq7ny4ltuarppvwdsn7p.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654942/zopiqnow/bqckm4986zwy45msium4.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654959/zopiqnow/jl6przyhboms1uili74y.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654977/zopiqnow/qjo3hsgfeu86ozrofjdx.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784654994/zopiqnow/zoytb0vkjldozvwfznxo.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655009/zopiqnow/yd9fyhssg8zhgkwbbgb3.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655027/zopiqnow/feojkexpd6hg7fvurlrm.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655042/zopiqnow/xdbzpaffk4vxi1cx5r0b.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655058/zopiqnow/ydsuvi68elajcdad831e.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655071/zopiqnow/g9mqhkjwej7hzp97cknv.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655087/zopiqnow/aappzmjwkbzl3ywjwir3.jpg'
   ],
   'Devotional Art', 0, 4),
  ('gs1-personalised-name', 'gs1',
   'Personalised Name Wall Hanging',
   'A name plate in mirror work, finished with evil eye beads and silky tassels. Made to order - tell us the name to paint.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784655104/zopiqnow/plykbbgw0mw3tob1aqgw.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655104/zopiqnow/plykbbgw0mw3tob1aqgw.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655113/zopiqnow/liwpd1r3m6xndzvjxtlo.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655122/zopiqnow/hrcv0vnreta2nozvk6v5.jpg'
   ],
   'Wall Hangings', 3, 1),
  ('gs1-red-lotus-plate', 'gs1',
   'Red Lotus Mandala Lippan Wall Plate',
   'A crimson and white lotus mandala with mirror inlay on a bold black rim. Handmade and one of a kind.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784655165/zopiqnow/wflsxi9xogx87r5p8jmo.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655165/zopiqnow/wflsxi9xogx87r5p8jmo.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655178/zopiqnow/h7ij8xyo9eni9jmjsr0l.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655185/zopiqnow/jabdq4fdrgntkriefowm.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655191/zopiqnow/oizuze6vn6mr46r9gpom.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655198/zopiqnow/hgh9qxpcsj4pzl6ke4mo.jpg'
   ],
   'Mandala and Lotus', 1, 2),
  ('gs1-krishnaya-mantra', 'gs1',
   'Krishnaya Vasudevaya Mantra Wall Plate',
   'The Krishnaya Vasudevaya mantra in raised gold lettering on deep red, surrounded by hand-painted peacock feathers and mirror flowers. A large centrepiece.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784655212/zopiqnow/hw0rbs7pvkzunzbkfymp.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655212/zopiqnow/hw0rbs7pvkzunzbkfymp.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655221/zopiqnow/pdlhbnetdiudlzyip3tj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655271/zopiqnow/ulqcuts1y1voajrq23en.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655279/zopiqnow/tn8skcjw7mas5qoo4jcs.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655294/zopiqnow/ujqpg3duvpzah8ixcgql.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655309/zopiqnow/n8zkp2scakqqy85zxrk7.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655323/zopiqnow/gukrhfclb7z9cemmmqli.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655333/zopiqnow/jeqnz8jgdk7ro9tmbhjj.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655347/zopiqnow/s2xtx0qmnq7aypxfdzxx.jpg'
   ],
   'Devotional Art', 0, 5),
  ('gs1-lotus-arch-panel', 'gs1',
   'Lotus and Mughal Arch Lippan Panel',
   'A tall panel with a mughal arch in fine mirror work, set against pink lotus vines on teal. Hand-painted throughout.',
   999,
   'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_600,c_limit/v1784655369/zopiqnow/sdvnmvmzthkr0h8scptn.jpg',
   array[
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655369/zopiqnow/sdvnmvmzthkr0h8scptn.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655390/zopiqnow/gxeeckjbhvx5rv6td0wd.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655423/zopiqnow/qmn7nyp9keitx1uvt6tk.jpg',
     'https://res.cloudinary.com/mqppsahn/image/upload/f_auto,q_auto,w_1200,c_limit/v1784655432/zopiqnow/lq4qv0w1fdhiuglemgk6.jpg'
   ],
   'Mandala and Lotus', 1, 3);
