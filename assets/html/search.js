/*
 * Part of Documenter.jl
 *     https://github.com/JuliaDocs/Documenter.jl
 *
 * License: MIT
 */

// parseUri 1.2.2
// (c) Steven Levithan <stevenlevithan.com>
// MIT License
function parseUri (str) {
	var	o   = parseUri.options,
		m   = o.parser[o.strictMode ? "strict" : "loose"].exec(str),
		uri = {},
		i   = 14;

	while (i--) uri[o.key[i]] = m[i] || "";

	uri[o.q.name] = {};
	uri[o.key[12]].replace(o.q.parser, function ($0, $1, $2) {
		if ($1) uri[o.q.name][$1] = $2;
	});

	return uri;
};
parseUri.options = {
	strictMode: false,
	key: ["source","protocol","authority","userInfo","user","password","host","port","relative","path","directory","file","query","anchor"],
	q:   {
		name:   "queryKey",
		parser: /(?:^|&)([^&=]*)=?([^&]*)/g
	},
	parser: {
		strict: /^(?:([^:\/?#]+):)?(?:\/\/((?:(([^:@]*)(?::([^:@]*))?)?@)?([^:\/?#]*)(?::(\d*))?))?((((?:[^?#\/]*\/)*)([^?#]*))(?:\?([^#]*))?(?:#(.*))?)/,
		loose:  /^(?:(?![^:@]+:[^:@\/]*@)([^:\/?#.]+):)?(?:\/\/)?((?:(([^:@]*)(?::([^:@]*))?)?@)?([^:\/?#]*)(?::(\d*))?)(((\/(?:[^?#](?![^?#\/]*\.[^?#\/.]+(?:[?#]|$)))*\/?)?([^?#\/]*))(?:\?([^#]*))?(?:#(.*))?)/
	}
};

requirejs.config({
    paths: {
        'jquery': 'https://cdnjs.cloudflare.com/ajax/libs/jquery/3.1.1/jquery.min',
        'lunr': 'https://cdnjs.cloudflare.com/ajax/libs/lunr.js/2.1.3/lunr.min',
    }
});

var currentScript = document.currentScript;

require(["jquery", "lunr"], function($, lunr) {
    // add . as a separator, because otherwise "title": "Documenter.Anchors.add!"
    // would not find anything if searching for "add!", only for the entire qualification
    lunr.tokenizer.separator = /[\s\-\.]+/

    // custom trimmer that doesn't strip @ and !, which are used in julia macro and function names
    lunr.trimmer = function (token) {
        return token.update(function (s) {
            return s.replace(/^[^a-zA-Z0-9@!]+/, '').replace(/[^a-zA-Z0-9@!]+$/, '')
        })
    }

    lunr.Pipeline.registerFunction(lunr.trimmer, 'juliatrimmer')

    var index = lunr(function () {
        this.ref('location')
        this.field('title')
        this.field('text')
        documenterSearchIndex['docs'].forEach(function(e) {
            this.add(e)
        }, this)
    })
    var store = {}

    documenterSearchIndex['docs'].forEach(function(e) {
        store[e.location] = {title: e.title, category: e.category}
    })

    $(function(){
        function update_search(querystring) {
            tokens = lunr.tokenizer(querystring)
            results = index.query(function (q) {
                tokens.forEach(function (t) {
                    q.term(t.toString())
                })
            })
            $('#search-info').text("Number of results: " + results.length)
            $('#search-results').empty()
            results.forEach(function(result) {
                data = store[result.ref]
                link = $('<a>')
                link.text(data.title)
                link.attr('href', documenterBaseURL+'/'+result.ref)
                cat = $('<span class="category">('+data.category+')</span>')
                li = $('<li>').append(link).append(cat)
                $('#search-results').append(li)
            })
        }

        function update_search_box() {
            querystring = $('#search-query').val()
            update_search(querystring)
        }

        $('#search-query').keyup(update_search_box)
        $('#search-query').change(update_search_box)

        search_query_uri = parseUri(window.location).queryKey["q"]
        if(search_query_uri !== undefined) {
            search_query = decodeURIComponent(search_query_uri.replace(/\+/g, '%20'))
            $("#search-query").val(search_query)
        }
        update_search_box();
    })
})
